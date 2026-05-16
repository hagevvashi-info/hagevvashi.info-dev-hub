# アトミシティとロック所有権の設計的考察

## 0. 本質的な問題提起

現在の実装（ToBe）が AsIs よりも複雑である理由は、単なる「ロック管理の可視化」ではなく、**アトミシティの所有権をどこに置くか** という根本的な設計判断にある。

```
処理A（並行実行される go func）
  ├─ ステップ1：セッション取得
  ├─ ステップ2：Agent 実行（時間がかかる）
  └─ ステップ3：sessionID 更新

問い：この一連の処理のアトミシティを誰が、どこで担保するか？
```

---

## 1. 設計パターンの比較

### 設計1：ロック隠蔽型（AsIs）

```go
// Manager の実装
func (m *ManagerImpl) GetOrCreate(msg) {
    m.mu.Lock()
    s := /* 取得ロジック */
    m.mu.Unlock()
    return s
}

func (m *ManagerImpl) UpdateSessionID(id) {
    m.mu.Lock()
    /* 更新ロジック */
    m.mu.Unlock()
}

// 呼び出し側（go func 内）
sess, created, err := brg.Sessions.GetOrCreate(msg)           // ロック1
if err != nil { return }

result, sessionID, _ := brg.Execute(msg, sess, created)       // ロック外（長時間）

// sessionID が更新されるのは、Execute 完了後
// 異なるスレッドの sessionID 更新と競合する可能性あり
```

**タイムライン**：

```
スレッド1：[LOCK] GetOrCreate → [UNLOCK] → Agent実行(3秒) → [LOCK] UpdateSessionID → [UNLOCK]
                                              ↓ この間に
スレッド2：                      [LOCK] GetOrCreate → [UNLOCK] → Agent実行 → ...
                                  （スレッド1とは異なる threadKey を処理中）
```

**アトミシティ**：
- GetOrCreate のみアトミック
- UpdateSessionID のみアトミック
- **全体のアトミシティはない**

---

### 設計2：ロック明示型（ToBe）

```go
// Manager の実装
func (m *ManagerImpl) Lock() {
    m.mu.Lock()
}

func (m *ManagerImpl) Unlock() {
    m.mu.Unlock()
}

func (m *ManagerImpl) GetOrCreateUnsafe(msg) {
    // ロック管理は呼び出し側の責任
    s := /* 取得ロジック */
    return s
}

func (m *ManagerImpl) UpdateSessionIDUnsafe(id) {
    // ロック管理は呼び出し側の責任
    /* 更新ロジック */
}

// 呼び出し側（go func 内）
brg.Sessions.Lock()
sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)     // ロック内
brg.Sessions.Unlock()

if err != nil { return }

result, sessionID, _ := brg.Execute(msg, sess, created)       // ロック外（長時間）

brg.Sessions.Lock()
if sessionID != "" {
    brg.Sessions.UpdateSessionIDUnsafe(threadKey, sessionID)  // ロック内
}
brg.Sessions.Unlock()
```

**タイムライン**：

```
スレッド1：[LOCK] GetOrCreateUnsafe → [UNLOCK] → Agent実行(3秒) → [LOCK] UpdateSessionIDUnsafe → [UNLOCK]
                                                     ↓ この間に
スレッド2：                           [LOCK] GetOrCreateUnsafe → [UNLOCK] → Agent実行 → ...
                                       （スレッド1のロック解放後に実行）
```

**アトミシティ**：
- GetOrCreateUnsafe のみアトミック（呼び出し側でロック）
- UpdateSessionIDUnsafe のみアトミック（呼び出し側でロック）
- **全体のアトミシティはない（設計上、不要）**

---

## 2. アトミシティとは何か？

### 定義

**アトミシティ（Atomicity）**：複数のステップが「一つの不可分な単位」として実行されることを保証する性質

```
アトミック：
ステップ1 → ステップ2 → ステップ3 
[一度始まったら割り込まれない]

非アトミック：
ステップ1 → ステップ2 → ステップ3
[途中で他のスレッドが割り込む可能性]
```

### このプロジェクトでアトミックである必要があること

```
セッション取得（ステップ1）：
  • 既存セッションがあれば返す
  • なければ新規作成
  → アトミックである必要がある（中途半端な状態は許さない）

sessionID 更新（ステップ3）：
  • セッションに sessionID を記録
  → アトミックである必要がある

ステップ1 + ステップ2 + ステップ3 の全体：
  → アトミックである必要があるか？
```

---

## 3. 重要な洞察：アトミシティの粒度

### 問題：「何がアトミックであるべきか」は設計判断

```
粒度1：何もアトミック（最大並行性）
┌───────────────────────────────┐
│ GetOrCreate()              ← ロック内
│ Agent.Execute()            ← ロック外
│ UpdateSessionID()          ← ロック内
└───────────────────────────────┘
↓
複数スレッドが GetOrCreate と UpdateSessionID の間に挟まる可能性

粒度2：各操作ごと（AsIs）
┌─────────────────────────────────┐
│ [LOCK] GetOrCreate [UNLOCK]    ← アトミック
│ Agent.Execute                   ← ロック外
│ [LOCK] UpdateSessionID [UNLOCK] ← アトミック
└─────────────────────────────────┘
↓
全体のアトミシティがない
でも、同じ threadKey は 1 go func で処理されるので問題ない

粒度3：全体（ToBe と同じ方式だが、Agent 実行もロック内）
┌────────────────────────────────┐
│ [LOCK]                         │
│   GetOrCreateUnsafe()          │
│   Agent.Execute()              ← 問題：ロック長時間保持
│   UpdateSessionIDUnsafe()      │
│ [UNLOCK]                       │
└────────────────────────────────┘
↓
全体のアトミシティがあるが、並行性が大幅に低下
```

---

## 4. ToBe 設計の意図

### ToBe の設計は「粒度2」を選択している

```go
brg.Sessions.Lock()
sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)
brg.Sessions.Unlock()

// ← ロック外で長時間処理
result, sessionID, _ := brg.Execute(msg, sess, created)

brg.Sessions.Lock()
if sessionID != "" {
    brg.Sessions.UpdateSessionIDUnsafe(threadKey, sessionID)
}
brg.Sessions.Unlock()
```

**設計判断**：
- GetOrCreateUnsafe のアトミシティ：✅ 必須
  - 既存セッションの取得と新規作成の競合を避ける
  
- UpdateSessionIDUnsafe のアトミシティ：✅ 必須
  - sessionID の更新を競合から保護
  
- 全体のアトミシティ：❌ 不要
  - 同じ threadKey は同じ go func でのみ処理される
  - 異なる threadKey 間の競合は許容

### なぜ全体のアトミシティが不要か？

```
ビジネスロジック：
• 各 threadKey は別個のスレッド（go func）で処理
• 同じ threadKey の GetOrCreate と Update は同じスレッドで順序保証
• 異なる threadKey 間では競合しない

// byThread は threadKey ごとにメッセージをグループ化
byThread := map[string][]message.Message{}
for _, msg := range messages {
    key, _ := msg.ThreadKey()
    byThread[key] = append(byThread[key], msg)
}

// 各スレッドが独立した threadKey を処理
for _, key := range threadKeys {
    go func(threadKey string, threadMsgs []message.Message) {
        // このスレッドは threadKey に関連する操作のみ
        // 同じ threadKey の別スレッドはない
    }(key, byThread[key])
}
```

---

## 5. AsIs と ToBe の本質的な違い

### AsIs：「操作ごとの独立性」を優先

```
GetOrCreate() → [内部ロック管理]
UpdateSessionID() → [内部ロック管理]

特徴：
• 呼び出し側は何も考えない
• 各操作が独立して並行安全
• だが、全体の一貫性は保証されない

使用例：
sess := GetOrCreate()      // ロック自動管理
Agent()                    // ロック外
UpdateSessionID()          // ロック自動管理
```

### ToBe：「呼び出し側が責任を持つ」を優先

```
Lock() / Unlock() を公開
GetOrCreateUnsafe() / UpdateSessionIDUnsafe() を提供

特徴：
• 呼び出し側がアトミシティの粒度を指定
• 呼び出し側が「何をアトミックにするか」を決定
• より細かいロック制御が可能

使用例：
brg.Sessions.Lock()
sess := GetOrCreateUnsafe()    // ロック内
brg.Sessions.Unlock()

brg.Sessions.Lock()
update := UpdateSessionIDUnsafe()  // ロック内
brg.Sessions.Unlock()
```

---

## 6. 設計のトレードオフ

### 表：隠蔽 vs 明示

| 項目 | AsIs（隠蔽） | ToBe（明示） |
|-----|-----------|-----------|
| **アトミシティの粒度** | 各操作 | 呼び出し側で指定 |
| **ロック管理の複雑性** | 低い（隠蔽） | 高い（明示） |
| **ロック時間** | 長い（操作ごと） | 短い（最小限） |
| **並行性** | 低い | 中程度 |
| **呼び出し側の負荷** | 低い | 高い |
| **バグのリスク** | Lock 忘れがない | Lock 忘れの可能性 |
| **パフォーマンス** | 低い（長ロック） | 高い（短ロック） |

---

## 7. アトミシティの必要性：ビジネスロジック依存

### このプロジェクトの場合

```
同じ threadKey は同じ go func でのみ処理
↓
GetOrCreate と UpdateSessionID の間に
別の threadKey の操作が挟まっても問題ない
↓
「各操作のアトミシティ」で十分
（全体のアトミシティは不要）
```

### 異なるシナリオの場合

```
もし複数の go func が同じ threadKey を処理する場合：
↓
GetOrCreate と UpdateSessionID が
別のスレッドに割り込まれる危険性あり
↓
全体のアトミシティが必要になる可能性
↓
粒度3（全体ロック）を選択すべき
```

---

## 8. API 設計の本質的な問題

### 隠蔽のジレンマ

```
隠蔽できることと、隠蔽できないことがある

隠蔽できる：
✅ GetOrCreate 内のロック管理
✅ 各操作の internal な一貫性

隠蔽できない：
❌ 複数操作のアトミシティ
  （= 呼び出し側の意図に依存）
```

### ToBe の判断

```
「複数操作のアトミシティは呼び出し側が決めるべき」
という設計判断

利点：
• 呼び出し側の意図が明確になる
• 過度なロック（全体ロック）を避けられる
• パフォーマンス最適化が可能

欠点：
• 呼び出し側が「ロックのルール」を理解する必要
• Safe/Unsafe 命名だけでは不十分
• ドキュメントが必須
```

---

## 9. 結論：設計の選択

### AsIs（隠蔽型）

```
メンタルモデル：
「Manager に任せておけば大丈夫」

現実：
「単純だが、全体の一貫性は保証されない」
「でも、このプロジェクトでは問題ない」
```

### ToBe（明示型）

```
メンタルモデル：
「自分たちのビジネスロジックに最適なロック粒度を選べる」

現実：
「複雑だが、柔軟で効率的」
「ドキュメントと規約が必須」
```

---

## 10. 推奨：ドキュメント化すべき項目

### 10.1 アトミシティの定義

```markdown
## セッション管理のアトミシティ保証

### 何がアトミックか？

1. **GetOrCreateUnsafe のアトミシティ**
   - 既存セッション取得と新規作成の排他制御
   - 複数スレッドが同時に GetOrCreateUnsafe を呼ぶ場合の保護
   - Lock/Unlock で囲むことで担保

2. **UpdateSessionIDUnsafe のアトミシティ**
   - sessionID の更新の排他制御
   - Lock/Unlock で囲むことで担保

### 何がアトミックでない（且つ不要）か？

- GetOrCreateUnsafe と UpdateSessionIDUnsafe の全体
- 理由：同じ threadKey は単一の go func でのみ処理されるため
```

### 10.2 Safe/Unsafe の明確な定義

```markdown
## Safe と Unsafe の定義

### GetOrCreateUnsafe

- **Unsafe である理由**：Lock で保護されていない
- **いつ呼んでいいのか**：Manager.Lock() の直後から Manager.Unlock() の直前まで
- **呼んではいけないとき**：Lock していない状態

### UpdateSessionIDUnsafe

- **Unsafe である理由**：Lock で保護されていない
- **いつ呼んでいいのか**：Manager.Lock() の直後から Manager.Unlock() の直前まで
- **呼んではいけないとき**：Lock していない状態
```

### 10.3 実装パターン

```markdown
## 正しい使い方

### パターン1：セッション取得

\`\`\`go
brg.Sessions.Lock()
sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)
brg.Sessions.Unlock()

if err != nil {
    // エラー処理
    return
}
\`\`\`

### パターン2：sessionID 更新

\`\`\`go
brg.Sessions.Lock()
if sessionID != "" {
    brg.Sessions.UpdateSessionIDUnsafe(threadKey, sessionID)
}
brg.Sessions.Unlock()
\`\`\`

### アンチパターン

\`\`\`go
// ❌ Lock し忘れ
sess, _ := brg.Sessions.GetOrCreateUnsafe(msg)

// ❌ Unlock し忘れ
brg.Sessions.Lock()
sess, _ := brg.Sessions.GetOrCreateUnsafe(msg)
// Unlock がない！

// ❌ UpdateSessionID（ロック内で呼ぶべき Unsafe を Lock 外で呼ぶ）
brg.Sessions.UpdateSessionIDUnsafe(key, id)  // ロック外！
\`\`\`
```

---

**作成日**：2026-05-16  
**重要度**：高（API 設計の本質に関わる）  
**対象バージョン**：PR #65 以降
