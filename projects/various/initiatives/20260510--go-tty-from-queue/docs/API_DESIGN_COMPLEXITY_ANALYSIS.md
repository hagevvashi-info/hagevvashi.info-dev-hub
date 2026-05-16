# API 設計の複雑性分析：Manager インターフェースの視点

## 0. 問題提起

前回のレポートは **go func 内のコード行数** にフォーカスしていました。しかし、本当の複雑性は **Manager インターフェースの API 設計** にあります。

実装の複雑性と同じくらい重要なのが：
- **API ユーザーが何をすべきか明確か？**
- **並行プログラミングの契約が一目で分かるか？**
- **Safe/Unsafe 命名が実際に効果的か？**

---

## 1. Manager インターフェースの進化

### 📋 AsIs（PR #64）

```go
type Manager interface {
    GetOrCreate(msg message.Message) (*AgentSession, bool, error)
    UpdateSessionID(threadKey, sessionID string)
}
```

**API の使い方**:
```go
sess, created, err := brg.Sessions.GetOrCreate(msg)
if err != nil {
    return err
}
brg.Execute(msg, sess, created)
```

**API ユーザーが知る必要があること**：
1. GetOrCreate を呼ぶ
2. UpdateSessionID を呼ぶ
3. **ロック管理は自動** ← 隠蔽されている

### 📋 ToBe（現在）

```go
type Manager interface {
    Lock()
    Unlock()
    GetOrCreateUnsafe(msg message.Message) (*AgentSession, bool, error)
    UpdateSessionIDUnsafe(threadKey, sessionID string)
}
```

**API の使い方**:
```go
brg.Sessions.Lock()
sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)
brg.Sessions.Unlock()

if err != nil {
    return err
}

result, sessionID, _ := brg.Execute(msg, sess, created)

brg.Sessions.Lock()
if sessionID != "" {
    brg.Sessions.UpdateSessionIDUnsafe(threadKey, sessionID)
}
brg.Sessions.Unlock()
```

**API ユーザーが知る必要があること**：
1. Lock/Unlock を明示的に呼ぶ必要がある
2. GetOrCreateUnsafe は **Lock の中でのみ呼べる**
3. UpdateSessionIDUnsafe は **Lock の中でのみ呼べる**
4. Lock/Unlock を忘れるとバグになる
5. Unsafe という名前の意味を理解する必要がある

---

## 2. API 設計の複雑性

### 2.1 呼び出しルールの複雑性

#### AsIs：呼び出しルール

```
┌────────────────────────────────┐
│ GetOrCreate()                  │
│  └─ 並行安全（自動処理）       │
│                                │
│ UpdateSessionID()              │
│  └─ 並行安全（自動処理）       │
└────────────────────────────────┘

ルール：なし
→ 何も考えずに呼んでOK
```

**ルール数：0**

#### ToBe：呼び出しルール

```
┌────────────────────────────────┐
│ Lock()                         │
│  ↓ [必須：最初に呼ぶ]          │
│ GetOrCreateUnsafe()            │
│  └─ Lock内でのみ呼び出し可能   │
│  ↓                             │
│ Unlock()                       │
│  └─ 最後に呼ぶ                 │
│                                │
│ Lock()                         │
│  ↓ [条件：sessionID != ""]     │
│ UpdateSessionIDUnsafe()        │
│  └─ Lock内でのみ呼び出し可能   │
│  ↓                             │
│ Unlock()                       │
└────────────────────────────────┘

ルール：
1. Lock を必ず最初に呼ぶ
2. GetOrCreateUnsafe は Lock内でのみ
3. Unlock を必ず最後に呼ぶ
4. 必要に応じて Lock/Unlock をもう一度
5. UpdateSessionIDUnsafe は Lock内でのみ
```

**ルール数：5**

### 2.2 ルールの明示性評価

#### AsIs

```
使う人の視点：
sess, created, err := brg.Sessions.GetOrCreate(msg)
↓
「何のルールもない。就呼ぶだけ」
↓
認知負荷：最小
```

**分かりやすさ**：⭐⭐⭐⭐⭐（最高）

#### ToBe

```
使う人の視点：
brg.Sessions.Lock()                              ← ？ なぜロック？
sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)  ← ？ Unsafe？
brg.Sessions.Unlock()                           ← ？ いつアンロック？

...

brg.Sessions.Lock()                             ← ？ なぜもう一度？
if sessionID != "" {                            ← ？ なぜチェック？
    brg.Sessions.UpdateSessionIDUnsafe(...)    ← ？ Unsafe？
}
brg.Sessions.Unlock()
↓
「ルールが多い。全部覚える必要がある」
↓
認知負荷：高
```

**分かりやすさ**：⭐⭐（低い）

---

## 3. Safe/Unsafe 命名が本当に効果的か？

### 3.1 Safe/Unsafe の定義

現在のコードでの Safe/Unsafe の定義：
- **Unsafe** = ロック内で呼ぶことを前提としたメソッド
- **Safe** = 呼び出し側でロック管理をする（自動ロック）

しかし、これはドキュメント化されていますか？

### 3.2 新規開発者の視点

```
UpdateSessionIDUnsafe という名前を見て、
開発者は何と思うか？

A. 「これはロック内で呼ぶ必要があるメソッドだ」
   → 正解（Safe/Unsafe の命名規則を知っている場合）

B. 「このメソッドは安全でない。バグの可能性がある」
   → 誤解（実装を見なければ不明確）

C. 「何となく非推奨なメソッドらしい。避けた方が良さそう」
   → 誤解（使う必要があるメソッド）

D. 「何のことか分からない」
   → 実装を見ないと理解不可
```

**Safe/Unsafe 命名の効果**：
- コンカレンシー経験者（A）には理解できる
- Go初心者（B, C, D）には分かりにくい

---

## 4. インターフェース設計の問題点

### 4.1 実装詳細の漏洩

#### AsIs

```go
type Manager interface {
    GetOrCreate(msg message.Message) (*AgentSession, bool, error)
    UpdateSessionID(threadKey, sessionID string)
}
```

このインターフェースから分かること：
- 何をするのか（GetOrCreate, UpdateSessionID）
- どんなパラメータが必要か
- **どうやるのか（実装詳細）は隠蔽**

#### ToBe

```go
type Manager interface {
    Lock()      ← sync.Mutex の存在が漏れている
    Unlock()    ← sync.Mutex の存在が漏れている
    GetOrCreateUnsafe(...)
    UpdateSessionIDUnsafe(...)
}
```

このインターフェースから分かること：
- 何をするのか
- **どうやるのか（Lock/Unlock = sync.Mutex）が漏れている**

**問題**：`Lock()` / `Unlock()` は `sync.Mutex` の実装詳細。API に含めるべきか？

### 4.2 並行プログラミングの契約が不明確

```go
// これはロック内で呼べるのか？呼べないのか？
sess, _ := brg.Sessions.GetOrCreateUnsafe(msg)

// ドキュメントを見ないと分からない
```

**AsIs なら**：
```go
// GetOrCreate は明らかに並行安全（Concurrent-Safe）
sess, _ := brg.Sessions.GetOrCreate(msg)
```

---

## 5. 並行プログラミングの契約の見え方

### 5.1 「このメソッドはいつ呼べるのか？」が分かるか？

#### 現在のコード例

```go
// Platform.PostResponse - ロック外で呼ぶ
brg.Platform.PostResponse(msg, result)

// Sessions.GetOrCreateUnsafe - ロック内で呼ぶ
brg.Sessions.Lock()
sess, _ := brg.Sessions.GetOrCreateUnsafe(msg)
brg.Sessions.Unlock()

// Execute - ロック外で呼ぶ
result, sessionID, _ := brg.Execute(msg, sess, created)
```

使う人が理解すること：
1. Platform のメソッドはロック外で呼べる
2. Sessions の Unsafe メソッドはロック内で呼ぶ
3. Bridge.Execute はロック外で呼ぶ

**問題**：
- Platform のメソッドはロック内で呼んでもいい？だめ？
- Execute はロック内で呼んでもいい？だめ？
- これらの「ルール」がコードから一目で分かるか？

**答え**：分かりにくい

---

## 6. テスト観点での複雑性

### 6.1 Mock の作成難易度

#### AsIs

```go
type MockManager struct {
    sessions map[string]*AgentSession
}

func (m *MockManager) GetOrCreate(msg message.Message) (*AgentSession, bool, error) {
    // ロック機構を考えずに実装できる
    return m.sessions[key], false, nil
}
```

**容易性**：簡単（ロック機構を気にしなくてOK）

#### ToBe

```go
type MockManager struct {
    mu       sync.Mutex  // Lock/Unlock のため必須！
    sessions map[string]*AgentSession
}

func (m *MockManager) Lock() {
    m.mu.Lock()
}

func (m *MockManager) Unlock() {
    m.mu.Unlock()
}

func (m *MockManager) GetOrCreateUnsafe(msg message.Message) (*AgentSession, bool, error) {
    // Lock されているはずという前提の下で実装
    return m.sessions[key], false, nil
}
```

**容易性**：難しい（実装詳細の sync.Mutex が必須）

---

## 7. 総合評価：API 設計の複雑性

### 表：API の複雑性比較

| 項目 | AsIs | ToBe | 悪化度 |
|-----|-----|-----|--------|
| **呼び出しルール数** | 0 | 5 | 大幅悪化 |
| **Safe/Unsafe の分かりやすさ** | N/A | 低い | 新規追加 |
| **実装詳細の漏洩** | なし | あり（Mutex） | 悪化 |
| **並行契約の明確性** | 不明確 | 明示的だが複雑 | 改善+悪化 |
| **Mock 作成難易度** | 簡単 | 難しい | 悪化 |
| **ドキュメント依存性** | 低い | 高い | 悪化 |

### 複雑性の本質

```
AsIs:
  API が単純 ← ロック管理が隠蔽
  ↓
  使う側は何も考えなくてOK
  ↓
  並行性が低い（長時間ロック）
  ↓
  性能が低い

ToBe:
  API が複雑 ← ロック管理を明示
  ↓
  使う側が5つのルールを覚える必要
  ↓
  並行性が高い（最小限ロック）
  ↓
  性能が高い
```

**トレードオフ**：
- シンプル API vs 高性能
- 習いやすさ vs 安全性

---

## 8. 使う人が「ぱっと分かる」か？

### 質問：Lock/Unlock を見て、一目で「ロック内で呼ぶ」と分かるか？

```go
brg.Sessions.Lock()
sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)  // ← Unsafe の意味、分かる？
brg.Sessions.Unlock()
```

### 経験層別の反応

| 開発者タイプ | 理解度 | 理由 |
|-----------|-------|------|
| **Go初心者** | 30% | Unsafe の意味不明、Lock の効果不明 |
| **Go初中級（コンカレンシー未経験）** | 60% | Unsafe = 危険？と勘違い |
| **Go中級（コンカレンシー経験）** | 95% | Lock/Unlock で「ああ、ロック内か」と理解 |
| **このプロジェクト経験者** | 100% | 実装を知っているので理解 |

**結論**：開発者のレベルに大きく依存

---

## 9. 改善提案

### 9.1 ドキュメント

```go
// Manager は セッション管理インターフェース
type Manager interface {
    // Lock はセッション状態を保護するミューテックスを取得します
    // Lock/Unlock で囲まれたコードでのみ GetOrCreateUnsafe / UpdateSessionIDUnsafe を呼び出してください
    Lock()
    
    // Unlock はロックを解放します
    Unlock()
    
    // GetOrCreateUnsafe はロック内でのみ呼び出し可能です（Lock を取得してから呼んでください）
    // 外側で Lock/Unlock で囲む必要があります
    // Safe な GetOrCreate() は存在しません。必ず Lock で囲んでください
    GetOrCreateUnsafe(msg message.Message) (*AgentSession, bool, error)
    
    // UpdateSessionIDUnsafe はロック内でのみ呼び出し可能です
    // 外側で Lock/Unlock で囲む必要があります
    UpdateSessionIDUnsafe(threadKey, sessionID string)
}
```

### 9.2 ヘルパーメソッドの提供

```go
// 代わりに、よく使う操作をヘルパーメソッドで提供
type Manager interface {
    Lock()
    Unlock()
    GetOrCreateUnsafe(msg message.Message) (*AgentSession, bool, error)
    UpdateSessionIDUnsafe(threadKey, sessionID string)
    
    // ↓ 新規追加
    // GetOrCreateSafe はロック管理を自動で行います（Lock/Unlock を含む）
    GetOrCreateSafe(msg message.Message) (*AgentSession, bool, error)
    
    // UpdateSessionIDSafe はロック管理を自動で行います（Lock/Unlock を含む）
    UpdateSessionIDSafe(threadKey, sessionID string) error
}
```

これなら使う人が選択できます：
```go
// 自分でロック管理する（パフォーマンス最適化時）
brg.Sessions.Lock()
sess, _ := brg.Sessions.GetOrCreateUnsafe(msg)
brg.Sessions.Unlock()

// または、自動ロック管理（シンプル）
sess, _ := brg.Sessions.GetOrCreateSafe(msg)
```

---

## 10. 結論：API 設計の複雑性

### 悪くなった点（API の視点）

| 項目 | 悪化内容 |
|-----|--------|
| **呼び出しルール** | 0個 → 5個 |
| **メソッド数** | 2個 → 4個 |
| **ドキュメント必須性** | 低い → 高い |
| **初心者向け友好性** | 高い → 低い |
| **Safe/Unsafe の明確性** | N/A → 曖昧 |

### 良くなった点（API の視点）

| 項目 | 改善内容 |
|-----|--------|
| **並行性制御の明示性** | 隠蔽 → 明示 |
| **ロック時間の最小化** | 長い → 短い |
| **パフォーマンス** | 低い → 高い |

### 最終結論

```
API 設計は シンプル性 と パフォーマンス のトレードオフ

AsIs：シンプルだが性能が低い
ToBe：複雑だが性能が高い

「ぱっと分かるか？」という問いに対して：
→ NO。ドキュメントなしでは理解困難
```

---

**作成日**：2026-05-16  
**対象バージョン**：PR #65 以降
