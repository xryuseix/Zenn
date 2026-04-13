---
title: "サプライチェーン攻撃に立ち向かうために、DIVER OSINT CTFが実施したNつのこと"
emoji: "🐼"
type: "tech" # tech: 技術記事 / idea: アイデア
topics:
  [
    "サプライチェーン攻撃",
    "サプライチェーンセキュリティ",
    "ソフトウェアサプライチェーン",
    "takumi",
    "takumiguard",
  ]
published: true
---

こんにちは、DIVER OSINT CTFの運営メンバーで主にインフラ周りを担当しています、xryuseixです。特に今年に入ってからサプライチェーン攻撃の脅威が顕著に現れ、対応が求められていますが、これはDIVER OSINT CTFの作問環境に関しても例外ではありませんでした。

そこで、この記事では、

1. **なぜDIVER OSINT CTFがサプライチェーン攻撃対策をやるのか**
2. **実際にどんな対策を実施したのか**

をお話ししていこうと思います。

## なぜDIVER OSINT CTFがサプライチェーン攻撃対策をやるのか

結論からお伝えすると、DIVER OSINT CTFにとって最も守るべきものは、**問題情報の漏洩を防ぐこと**と、**運営メンバーが作問ツールを安全に開発できること**です。

[DIVER OSINT CTF](https://diverctf.org/)は問題の作成からデプロイに至るまで、[GitHub Actions](https://docs.github.com/ja/actions)やOSSの作問ツールといった多くの外部コンポーネントに依存しています。GitHubの[DIVER OSINT CTF Org.](https://github.com/diver-osint-ctf/)ではプライベートリポジトリを含めると40近くのリポジトリが存在しており、Attack Surfaceは決して少なくありません。

実際に、[aquasecurity/trivy-action](https://github.com/aquasecurity/trivy/discussions/10425)ではメンテナーの認証情報が悪用され、CI/CD上のシークレットが窃取され、[axios](https://github.com/axios/axios/issues/10604)では悪意ある依存が追加され、`postinstall`スクリプト経由でRATが配布されるなど、信頼していたコンポーネントが攻撃の起点になる事例が相次いでいます。こうした攻撃がDIVER OSINT CTFの運営基盤に及べば、問題情報の漏洩や開発環境の侵害に直結します。

そこで、DIVER OSINT CTFの運営基盤全体を見直し、サプライチェーン攻撃を「防ぐ」ための対策と、万が一侵害が起きた場合に「追跡する」ための仕組みを整備しました。

## ファイル別: 攻撃を未然に防ぐために実施したこと

### Dockerfile, docker-compose.ymlに対して

DIVER OSINT CTFでは、[diver-osint-ctf/ctfd-config-generator](https://github.com/diver-osint-ctf/ctfd-config-generator)等の作問ツールをDockerコンテナ内で実行するようにしています。これらが参照するコンテナイメージに対して、以下の対策を行いました。

- SHA Pinningを設定
  - 主に`FROM node:alpine3.22`みたいな記載や、`image: golang:1.24`のような記載に対して、以下のコードブロックのようにsha256のハッシュ値を設定します
  - これと同時に、`latest`はやめて特定のバージョンを指定します
- 信頼できるベースイメージのみを使用
  - Docker公式イメージや、信頼できるpublisherのイメージのみを使用するようにしています
- Dockerfile内でファイルをダウンロードする場合はsha256チェックを実施
  - `curl`/`wget`等で外部バイナリを取得する場合、ダウンロード後にsha256ハッシュを検証しています。なお後述の[suzuki-shunsuke/pinact](https://github.com/suzuki-shunsuke/pinact)用の`docker-compose.yml`にも記載しています

docker-compose.ymlのSHA Pinningの参考:

```yaml
services:
  app:
    image: golang:1.24@sha256:d2d2bc1c84f7e60d7d2438a3836ae7d0c847f4888464e7ec9ba3a1339a1ee804
```

### devcontainer.jsonに対して

運営メンバーの作問ツールの開発環境は基本的に[devcontainer](https://containers.dev/)で統一しています。これは、ローカル環境で`npm install`等のインストールスクリプトが実行されることを防いだり、悪意のあるパッケージを含めてビルドしてしまわないようにするためです。`devcontainer.json`にもコンテナイメージの指定があるため、同様の対策を適用しました。

- SHA Pinningを設定
  - Dockerfileと同様に、`"image": "mcr.microsoft.com/devcontainers/go:1.24"`のような記載に対して、SHAダイジェストを付与します
- 信頼できるベースイメージのみを使用
  - Dockerfileと同様です

### [.github/workflowsファイル](https://docs.github.com/ja/actions/concepts/workflows-and-actions/workflows)

DIVER OSINT CTFでは、問題のビルド・デプロイ・依存関係の検証などをCI/CDで自動化しています。例えば、問題の追加PRが作成された時に、以下のようなCIが6つくらい走ります。

- 画像が入っていればExifに意図していない情報が含まれていないか
- 問題文にtypoがないか
- 問題の依存関係(問題Aを解く前に問題Bをとかないといけない、など)が意図した通りかどうか

![swimmer_deps](/images/supplychain/swimmer_deps.png)
*SWIMMER OSINT CTF 2025では`briefingジャンル`→`多くの問題`→`ops_swimmerジャンル`のように、問題を解く順序が決まっていました。*

ここが侵害されるとシークレットの窃取や問題情報の漏洩に直結するため、最も重点的に対策を行いました。

- SHA Pinningを設定
  - `uses: actions/setup-go@6.4.0`みたいな記載に対して行います
  - これと同時に、`latest`や`@main`などはやめて特定のバージョンを指定します
  - [suzuki-shunsuke/pinact](https://github.com/suzuki-shunsuke/pinact)というツールがこれを一括でやってくれて便利です
- GitHub上でSHA Pinningがされていないアクションの実行を制限
  - `Settings` > `Actions` > `General` > `Require actions to be pinned to a full-length commit SHA`
  - 参考: <https://github.blog/changelog/2025-08-15-github-actions-policy-now-supports-blocking-and-sha-pinning-actions/>
- ワークフロー内でファイルをダウンロードする場合はsha256チェックを実施
  - `curl`や`wget`で外部からバイナリを取得するステップがある場合、ダウンロード後にsha256ハッシュを検証するようにしました
- [`permissions`](https://docs.github.com/ja/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token)の最小権限化
  - ワークフローのトップレベルに`permissions: read-all`等を設定し、各ジョブだけに必要な権限のみを付与しました
- `${{ }}`式のスクリプトインジェクション対策
  - `run:`ステップ内で`echo "${{ steps.pr_info.outputs.pr_head_ref }}"`のように`${{ }}`式を直接展開すると、攻撃者がブランチ名やPRタイトルに任意のコマンドを仕込むことでスクリプトインジェクションが成立します。対策として、`${{ }}`式の値を一度環境変数に格納してから参照するようにしました
  - 参考: https://www.stepsecurity.io/blog/hackerbot-claw-github-actions-exploitation
- [`issue_comment`](https://docs.github.com/ja/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#issue_comment)トリガーの実行者制限
  - ワークフローの中には、PR内のコメントで起動するものがあります。外部ユーザーのコメントで任意のワークフローが起動されないよう、[`author_association`](https://docs.github.com/ja/graphql/reference/enums#commentauthorassociation)が`OWNER`・`MEMBER`・`COLLABORATOR`のいずれかである場合のみ実行されるよう、各リポジトリの要件に合わせて制限しました
- [Takumi Guard Action](https://github.com/flatt-security/setup-takumi-guard-npm)の導入
  - ワークフロー内のnpmのレジストリを[Takumi Guard](https://flatt.tech/takumi/features/guard)のプロキシ(`npm.flatt.tech`)に差し替えることで、`npm install`時に悪意あるパッケージをインストール前にブロックしてくれるようにしました

GitHub Workflow fileの参考:
https://github.com/diver-osint-ctf/diver-osint-ctf.github.io/blob/53582d64498dc3fe14878c5394bbb42026aa3139/.github/workflows/deploy.yml#L18-L20

ところで、[suzuki-shunsuke/pinact](https://github.com/suzuki-shunsuke/pinact)自体がサプライチェーン攻撃くらったら終わりでは？と思ったので、こんな`docker-compose.yml`を作って、`pinact`コマンドで動くようにしました。

docker-compose.yml:

```yaml
# zshrcにこれを入れる
# pinact() {
#   docker compose -f /path/to/docker-compose.yml run --rm pinact
# }
services:
  pinact:
    # pinned 2026-04-05T04:56:17+09:00 golang:1.24 from registry-1.docker.io/library/golang:1.24
    image: golang:1.24@sha256:d2d2bc1c84f7e60d7d2438a3836ae7d0c847f4888464e7ec9ba3a1339a1ee804
    volumes:
      - ${PWD}/.github:/app/.github
    working_dir: /app
    entrypoint:
      - bash
      - -c
      - |
        set -euo pipefail
        PINACT_VERSION=v3.9.0
        ARCH=$$(uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')
        case "$$ARCH" in
          amd64) PINACT_SHA256=3829da718de38b1e914b974c3e77045a256999af84789437a7305b09130d8a6a ;;
          arm64) PINACT_SHA256=34a957423002662c6289782b571660beda6a37449a76d763c8ad8b1b9a500a54 ;;
        esac
        curl -fsSL -o /tmp/pinact.tar.gz "https://github.com/suzuki-shunsuke/pinact/releases/download/$${PINACT_VERSION}/pinact_linux_$${ARCH}.tar.gz"
        echo "$${PINACT_SHA256}  /tmp/pinact.tar.gz" | sha256sum -c -
        tar xz -C /usr/local/bin pinact < /tmp/pinact.tar.gz
        rm /tmp/pinact.tar.gz
        pinact run
```

### action.ymlファイルに対して

DIVER OSINT CTFで使用しているCI/CDツールのいくつかは、[GitHub Marketplace](https://github.com/marketplace)で公開しています(例: [diver-osint-ctf/challenge_dependencies](https://github.com/diver-osint-ctf/challenge_dependencies))。action.ymlはその公開用の設定ファイルです。

- SHA Pinningを設定
  - action.yml内で参照するアクションも、GitHub Workflow fileと同様にSHAでピン留めします
- `${{ }}`式のインジェクション対策
  - action.ymlは外部のユーザーが利用するため、入力値を信頼せず環境変数経由で参照するようにしました
- 外部入力を引数に渡す際のインジェクション対策
  - シェルスクリプトで外部入力を引数に渡すとき、文字列結合だとスペースや特殊文字で[Word Splitting](https://www.gnu.org/software/bash/manual/html_node/Word-Splitting.html)が起きる可能性があります。`ARGS=(...)`と`"${ARGS[@]}"`のようにbash配列で組み立てることで、これを防いでいます
- 入力値のバリデーション
  - action.ymlの`inputs`で受け取る値に対して、許可リストによるチェックを行っています(とはいえこれはサプライチェーン関係なく、ただのバグを減らすためのバリデーションな気がします)

```yaml
- name: Setup Go
  uses: actions/setup-go@4a3601121dd01d1626a1e23e37211e3254c1c06c # v6.4.0
```

### ローカル環境に対して

- Takumi Guardの導入
  - 開発環境は基本的にdevcontainerで動作するようにしましたが、Webアプリケーションを誤ってローカルにインストールしてしまった場合や、他のツール(brewなど)でインストールするときにnpm installが自動的に呼ばれる可能性があるため、[Takumi Guard](https://flatt.tech/takumi/features/guard)を導入しました。導入はコマンド1つかつ無料です！

### その他

上記のファイル単位の対策に加えて、依存するランタイムやパッケージマネージャ自体を減らすことでAttack Surfaceを小さくしました。

- 全ての内製ツールをGoで書き直した
  - もともと[Deno](https://deno.com/)とGoが混在していた内製ツールを、全てGoに統一しました
  - Goを選んだ理由は、[npm](https://www.npmjs.com/)のように`preinstall`/`postinstall`スクリプトが自動実行される仕組みがなく、先述のaxiosのような攻撃が構造的に成立しにくいためです。また、依存関係は`go.sum`のハッシュで検証されるため、改ざんがあればビルド時に検知できます
  - とはいえ、WebアプリケーションのフロントエンドはJS/TSで実装されているため、npm依存を完全にゼロにはできていません。この部分はTakumi Guardやdevcontainerによるリスクの隔離で対応しています
- `go.sum`や`package-lock.json`等のチェックサム・ロックファイルをコミット
  - 依存関係のハッシュをリポジトリに含めることで、意図しないバージョンへの差し替えをビルド時に検知できます

## 攻撃を追跡するために実施したこと

ここまでは攻撃を未然に防ぐための対策を紹介しましたが、万が一攻撃が発生した場合に備えて、追跡・調査を可能にする仕組みも導入しています。

### Takumi Runnerの導入

[Takumi Runner](https://flatt.tech/takumi/features/runner)とは、[GMO Flatt Security株式会社](https://flatt.tech/)(弊社)が提供する、GitHub Actionsのサプライチェーン攻撃対策のためのSelf Hosted Runnerです。[eBPF](https://ebpf.io/)等の技術を用いてCI/CDパイプライン上のプロセス・ネットワーク通信・ファイルアクセスなどを可視化してくれるため、サプライチェーン攻撃発生時の調査に役立ちます。

![runner_overview](/images/supplychain/runner_overview.png)

DIVER OSINT CTFでは、全てのワークフローを`runs-on: [takumi-runner]`と設定することでTakumi Runner上で実行しています。これにより、全CI/CDパイプラインの挙動が常に記録され、異常な通信やファイルアクセスが発生した場合に追跡可能な状態を維持しています。

https://github.com/diver-osint-ctf/diver-osint-ctf.github.io/blob/53582d64498dc3fe14878c5394bbb42026aa3139/.github/workflows/deploy.yml#L15-L17

例えば、以下の画像のようにどんなネットワークリクエストが走っているか確認できたり、

![runner_network](/images/supplychain/runner_network.png)

Workflowファイルのどの行がどんなプロセスを実行しているのか一目で確認できます。

![runner_timeline](/images/supplychain/runner_timeline.png)

なお、Takumi Runnerの利用は有料ですが、DIVER OSINT CTFは弊社とパートナー契約を結びました。そのため、Takumi Runnerを無料で使用させていただいています。

https://x.com/DIVER_OSINT_CTF/status/2043671941979287784?s=20

## まとめ

この記事では、DIVER OSINT CTFの運営基盤に対して行ったサプライチェーン攻撃対策を紹介しました。SHA Pinning・最小権限化・インジェクション対策といった「防御」と、Takumi Runnerによる「追跡」の両面からアプローチを行いました。

一方で、SHA Pinningした依存のバージョン管理は課題として残っています。ピン留めは改ざん防止には有効ですが、古いバージョンに固定されたまま脆弱性が放置されるリスクもあります。Dockerイメージ・GitHub Actions・Go modules・npmパッケージなど、対象ごとに更新手段が異なるため、これらを横断的に管理できるツールや仕組みがあると理想的とは思っています。

ここまでお読みいただきありがとうございました。DIVER OSINT CTF 2026の開催に向けて、我々はこれからも準備を進めてまいります。
