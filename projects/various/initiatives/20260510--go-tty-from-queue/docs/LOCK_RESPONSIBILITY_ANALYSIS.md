# ロック責務の分析：実装側の atomic性責務と現在の実装の整合性

## 0. 核心的な問い

**実装側の責務：実装が自分のアトミシティを守る責務がある**

```
GetOrCreate：「既存取得と新規作成」を atomic にする責務がある
UpdateSessionID：「sessionID 更新」を atomic にする責務がある
```

**問い：現在の ToBe 実装は、この責務を果たしているか？**

---

## 1. GetOrCreateUnsafe の責務分析

### 実装側の責務

```
「既存セッションの取得」と「新規セッション作成」は、
同じロック内で実行されなければならない

理由：
- 複数スレッドが同時に「既存判定」をした場合、
  どちらも「存在しない」と判定する可能性
- その結果、同じセッションが2個作成される
- → atomic性が必要
```

### 現在の実装

```go
// session.go
func (sm *ManagerImpl) GetOrCreateUnsafe(msg message.Message) (*AgentSession, bool, error) {
    key, err := msg.ThreadKey()
    if err != nil {
        return nil, false, err
    }

    now := time.Now()
    isThreadRoot := msg.IsThreadRoot()

    if s, ok := sm.sessions[key]; ok && !isThreadRoot {
        s.LastUsedAt = now
        return s, false, nil  // ← 既存返却
    }

    s := &AgentSession{...}
    sm.sessions[key] = s
    if err := sm.persistLocked(); err != nil {
        fmt.Fprintf(os.Stderr, "Warning: ...")
    }
    return s, true, nil  // ← 新規作成
}
```

**問題：「Unsafe」という名前だけで、ロック管理の責務が不明確**

現在の呼び出し方：
```go
brg.Sessions.Lock()
sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)
brg.Sessions.Unlock()
```

✅ **責務を果たしている**：
- 呼び出し側が Lock で囲むことで、GetOrCreateUnsafe は ロック内で実行される
- 「既存判定と新規作成」が atomic に実行される
- GetOrCreateUnsafe の責務：「ロック保護を前提とした操作」を提供する
- 呼び出し側の責務：「Lock で囲む」

---

## 2. UpdateSessionIDUnsafe の責務分析

### 実装側の責務

```
「sessionID の更新」は、
同じロック内で実行されなければならない

理由：
- 複数スレッドが同時に sessionID を更新した場合、
  最後の更新が反映される必要がある
- 読み取り→更新のタイミングで別スレッドが割り込まないこと
- → atomic性が必要
```

### 現在の実装

```go
// session.go
func (sm *ManagerImpl) UpdateSessionIDUnsafe(threadKey string, sessionID string) {
    if strings.TrimSpace(threadKey) == "" || strings.TrimSpace(sessionID) == "" {
        return
    }
    s, ok := sm.sessions[threadKey]
    if !ok {
        return
    }
    s.SessionID = sessionID
    s.LastUsedAt = time.Now()
    if err := sm.persistLocked(); err != nil {
        fmt.Fprintf(os.Stderr, "Warning: ...")
    }
}
```

**問題：「Unsafe」という名前だけで、ロック管理の責務が不明確**

現在の呼び出し方：
```go
brg.Sessions.Lock()
if sessionID != "" {
    brg.Sessions.UpdateSessionIDUnsafe(threadKey, sessionID)
}
brg.Sessions.Unlock()
```

✅ **責務を果たしている**：
- 呼び出し側が Lock で囲むことで、UpdateSessionIDUnsafe はロック内で実行される
- sessionID の更新が atomic に実行される
- UpdateSessionIDUnsafe の責務：「ロック保護を前提とした操作」を提供する
- 呼び出し側の責務：「Lock で囲む」

---

## 3. 全体フロー検証

### go func 内のロック管理

```go
go func(threadKey string, threadMsgs []message.Message) {
    // ステップ1：セッション取得の atomic性
    brg.Sessions.Lock()                                    // ← Lock 取得
    sess, created, err := brg.Sessions.GetOrCreateUnsafe(msg)
    brg.Sessions.Unlock()                                  // ← Lock 解放

    if err != nil {
        brg.Platform.PostResponse(msg, "❌...")            // ロック外OK
        return
    }

    // ステップ2：Agent 実行（ロック不要）
    result, sessionID, _ := brg.Execute(msg, sess, created)  // ロック外OK

    // ステップ3：sessionID 更新の atomic性
    brg.Sessions.Lock()                                    // ← Lock 取得
    if sessionID != "" {
        brg.Sessions.UpdateSessionIDUnsafe(threadKey, sessionID)
    }
    brg.Sessions.Unlock()                                  // ← Lock 解放

    brg.Platform.PostResponse(msg, result)                 // ロック外OK

    for _, origMsg := range threadMsgs {
        brg.Platform.MarkProcessed(origMsg.ID)             // ロック外OK
    }
}(key, msgs)
```

### 各ステップの atomic性責務

| ステップ | 操作 | Unsafe性 | 責務の所在 | 検証 |
|---------|------|---------|----------|------|
| 1 | GetOrCreateUnsafe | Unsafe | 呼び出し側がLock | ✅ Lock で囲まれている |
| 2 | Execute | Safe | Bridge実装 | ✅ ロック外で実行（OK） |
| 3 | UpdateSessionIDUnsafe | Unsafe | 呼び出し側がLock | ✅ Lock で囲まれている |

**結論：すべての Unsafe 操作が適切に Lock で保護されている**

---

## 4. 「実装側の責務」との整合性確認

### GetOrCreateUnsafe

**実装側の責務**：「既存判定と新規作成を atomic にする」
```go
func (sm *ManagerImpl) GetOrCreateUnsafe(msg) {
    // この関数の内部は atomic である必要がある
    // = ロック内で実行されることを前提
    if existing := sm.sessions[key]; existing != nil {
        return existing  // ← atomic な読み取り
    }
    sm.sessions[key] = newSession  // ← atomic な書き込み
}
```

**呼び出し側の責務**：「Lock で保護する」
```go
brg.Sessions.Lock()
sess := brg.Sessions.GetOrCreateUnsafe(msg)  // ← ロック内で実行
brg.Sessions.Unlock()
```

✅ **整合性：あり**

### UpdateSessionIDUnsafe

**実装側の責務**：「sessionID 更新を atomic にする」
```go
func (sm *ManagerImpl) UpdateSessionIDUnsafe(threadKey, sessionID) {
    // この関数の内部は atomic である必要がある
    // = ロック内で実行されることを前提
    s := sm.sessions[threadKey]
    s.SessionID = sessionID  // ← atomic な更新
}
```

**呼び出し側の責務**：「Lock で保護する」
```go
brg.Sessions.Lock()
if sessionID != "" {
    brg.Sessions.UpdateSessionIDUnsafe(threadKey, sessionID)  // ← ロック内で実行
}
brg.Sessions.Unlock()
```

✅ **整合性：あり**

---

## 5. 設計パターンの一貫性

### パターン：実装側がアトミシティ責務を定義、呼び出し側がそれを遵守

```
実装側（GetOrCreateUnsafe / UpdateSessionIDUnsafe）：
├─ 「Unsafe」という名前で、ロック保護を前提と宣言
├─ 実装はロック内で実行される前提で記述
└─ atomic な操作を提供

呼び出し側（go func）：
├─ 「Lock で囲む」という明示的な指示に従う
├─ Unsafe メソッドを Lock 内で実行
└─ 実装側の atomic性責務を尊重
```

**この設計パターンは一貫性がある** ✅

---

## 6. 潜在的な問題点と対策

### 問題1：新規開発者が「Unsafe」の意味を理解しない

```
GetOrCreateUnsafe という名前を見て、
「危険なメソッドだから避けるべき」と誤解する可能性
```

**対策**：ドキュメント化
```markdown
## Unsafe の定義

Unsafe は「実装の atomic性が呼び出し側のロック管理に依存する」という意味です。

GetOrCreateUnsafe：
- 呼び出し側が Lock/Unlock で囲む必要がある
- Lock 外で呼び出すと、race condition が発生する
- 「危険」ではなく「責務を呼び出し側に委譲」している
```

### 問題2：誰かが Lock 外で Unsafe メソッドを呼んでしまう

```go
// ❌ 間違った使い方
sess, _ := brg.Sessions.GetOrCreateUnsafe(msg)  // Lock なし！
```

**対策1**：コード審査で指摘
**対策2**：Go の lint ツール（あれば）
**対策3**：テストで race condition を検出
```bash
go test -race ./...
```

### 問題3：Lock のネストやデッドロック

```go
brg.Sessions.Lock()
sess := brg.Sessions.GetOrCreateUnsafe(msg)
// もし GetOrCreateUnsafe 内で再び Lock しようとしたら？
// → Deadlock！
```

**対策**：GetOrCreateUnsafe の実装で「Lock を再度取らない」ことを確認
```go
// ✅ 正しい実装
func (sm *ManagerImpl) GetOrCreateUnsafe(msg) {
    // Lock を取らない（呼び出し側が Lock を取っていることを前提）
    if s, ok := sm.sessions[key]; ok {
        return s, false, nil
    }
    // ...
}

// ❌ 間違った実装
func (sm *ManagerImpl) GetOrCreateUnsafe(msg) {
    sm.Mu.Lock()  // ← Deadlock の危険！
    // ...
    sm.Mu.Unlock()
}
```

**現在の実装は正しい** ✅

---

## 7. 最終検証チェックリスト

### 実装側の責務

- [x] GetOrCreateUnsafe：「既存判定と新規作成」を atomic にする責務がある
  - [x] 実装：ロック内で実行されることを前提に記述
  - [x] Lock を内部で取らない
  
- [x] UpdateSessionIDUnsafe：「sessionID 更新」を atomic にする責務がある
  - [x] 実装：ロック内で実行されることを前提に記述
  - [x] Lock を内部で取らない

### 呼び出し側の責務

- [x] GetOrCreateUnsafe は Lock で囲んで呼ぶ
  - [x] 現在の実装：103-105行で Lock で囲んでいる

- [x] UpdateSessionIDUnsafe は Lock で囲んで呼ぶ
  - [x] 現在の実装：114-118行で Lock で囲んでいる

- [x] ロック外で Unsafe メソッドを呼ばない
  - [x] 現在の実装：正しい

### アトミシティの粒度

- [x] GetOrCreateUnsafe のアトミシティ：✅ 担保
- [x] UpdateSessionIDUnsafe のアトミシティ：✅ 担保
- [x] 複数操作の atomic性：❌ 不要（同一 threadKey は単一 go func）
  - [x] 現在の実装：正しい（複数操作は atomic でない）

---

## 8. 結論

### 現在の ToBe 実装は、「実装側の atomic性責務」と整合している

```
✅ GetOrCreateUnsafe：atomic性責務を果たしている
✅ UpdateSessionIDUnsafe：atomic性責務を果たしている
✅ 呼び出し側：Lock で適切に保護している
✅ アトミシティの粒度：正しい（不要な全体ロックを避けている）
```

### 問題なし、修正不要

---

## 9. 推奨：ドキュメント化

これだけの分析をしていても、新規開発者は「Unsafe」の意味を理解しない可能性が高い。

以下をドキュメント化すること：
1. **Unsafe の定義**（責務の委譲を明記）
2. **正しい使い方**（Lock で囲む例）
3. **アンチパターン**（Lock 忘れ、ネストなど）
4. **atomic性の粒度**（なぜ複数操作を atomic にしないのか）

---

**作成日**：2026-05-16  
**結論**：現在の実装は方針と一致している。修正不要。
