# VSCode Copilot Chat設定ガイド

VSCodeでCopilot Chatを効果的に使用するための設定とアクセス方法について説明します。

## 🚀 Copilot Chatへのアクセス方法

### 1. チャットパネルを開く
- **サイドバーのCopilotアイコン**をクリック
- または **Ctrl+Shift+I** (Windows/Linux) / **Cmd+Shift+I** (Mac)

### 2. インラインチャット
- **Ctrl+I** (Windows/Linux) / **Cmd+I** (Mac)
- エディタ内で直接チャットを開始

### 3. コマンドパレット経由
- **Ctrl+Shift+P** → "Copilot: Open Chat" を検索

## 🎛️ チャット機能の詳細設定

### Agent、Ask、Editの切り替え方法

#### 方法1: チャット入力欄でのコマンド
```
@agent プロジェクトのアーキテクチャについて相談したい
/ask この関数の動作を教えて
/edit このコードを最適化して
```

#### 方法2: 画面上部のタブ切り替え
- チャットパネル上部に表示される **Agent**、**Ask**、**Edit** タブをクリック

#### 方法3: 右クリックメニュー
- コードを選択 → 右クリック → **Copilot** → 任意の機能を選択

## 🛠️ 各機能のキーボードショートカット

| 機能 | ショートカット | 説明 |
|------|----------------|------|
| **Agent Chat** | `Ctrl+Shift+I` | 総合的なAIアシスタント |
| **Inline Chat** | `Ctrl+I` | コード内での直接対話 |
| **Edit Mode** | `Ctrl+K` → `Ctrl+I` | 選択範囲の編集提案 |
| **Explain Code** | 右クリック → Copilot | 選択コードの説明 |

## 📋 使用時のベストプラクティス

### 1. 明確な指示を出す
```
❌ 曖昧: "このコードを良くして"
✅ 具体的: "この関数のパフォーマンスを改善し、エラーハンドリングを追加して"
```

### 2. コンテキストを提供する
```
✅ 良い例:
"Reactコンポーネントで、ユーザーリストを表示する際に
ページネーション機能を追加したいです。
現在のstateはusersとcurrentPageを管理しています。"
```

### 3. 段階的にアプローチする
1. **Ask**: 基本概念を理解
2. **Agent**: 実装方針を相談
3. **Edit**: 具体的なコード修正

## 🔧 トラブルシューティング

### 機能が表示されない場合
1. **GitHub Copilot拡張機能**がインストールされているか確認
2. **GitHub Copilotライセンス**が有効か確認
3. VSCodeを**最新版に更新**
4. 拡張機能を**再読み込み**

### チャットが応答しない場合
1. **インターネット接続**を確認
2. **GitHubアカウント**でサインイン済みか確認
3. **出力パネル**でエラーログを確認
4. VSCodeを**再起動**

## 💡 効率的な使い方のコツ

### プロジェクトファイルを開いた状態で使用
- Copilotは開いているファイルのコンテキストを理解してより適切な回答を提供

### 具体的なコード例と一緒に質問
- 実際のコードを見せることで、より精密なアドバイスを受けられる

### 継続的な対話
- 一度の質問で完璧な答えを求めず、段階的に詳細化していく

## 📖 関連リソース

- [GitHub Copilot公式ドキュメント](https://docs.github.com/copilot)
- [VSCode Copilot拡張機能](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot)
- [Copilot Chat使用例集](https://github.com/microsoft/vscode-docs/blob/main/docs/copilot/copilot-chat.md)