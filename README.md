# Zenn Articles

[Zenn CLI](https://zenn.dev/zenn/articles/install-zenn-cli) を使った記事管理リポジトリです。

```bash
# セットアップ
docker build -t zenn .

# 記事のプレビュー
docker run --rm -p 8000:8000 -v $(pwd)/articles:/app/articles -v $(pwd)/images:/app/images zenn preview

# 新しい記事の作成
docker run --rm -v $(pwd)/articles:/app/articles zenn new:article <slug>
```
