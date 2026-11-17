# Level 5 · Enforcement: bốn lớp kiểm tra

Mục tiêu L5: chuyển quy tắc từ "ghi trong file hướng dẫn và hy vọng agent làm theo" sang "máy kiểm tra, không thể quên, không thể bỏ qua".

- **Speed metric:** comment "cơ học" trong review của người = **0 mỗi PR**
- **Quality metric:** lỗi lint, type hoặc secret lọt tới CI = **0**

## Tổng quan

| Lớp              | Thời điểm                  | Chạy ở đâu                      | Vai trò                            |
| ---------------- | -------------------------- | ------------------------------- | ---------------------------------- |
| 1 · Agent hooks  | Agent sửa code             | Trong session của agent (local) | Phản hồi nhanh, có thể bị bỏ qua   |
| 2 · Git hooks    | `git commit`, `git push`   | Máy dev (local)                 | Phản hồi nhanh, có thể bị bỏ qua   |
| 3 · CI gate      | Mở / cập nhật pull request | GitHub Actions runner           | Cổng quyết định, không bypass được |
| 4 · Merge policy | Merge vào `main`           | GitHub server                   | Cổng quyết định, không bypass được |

---

## Lớp 1 · Agent hooks

_Chạy trong session của agent (máy local)._

### 1a. Trước khi agent chạy lệnh hoặc đọc / sửa file: `PreToolUse` (tức thì)

**Mục đích:** chặn hành động nguy hiểm hoặc truy cập secret _trước khi_ nó xảy ra, vì nhiều hành động (xóa file, force push, đọc `.env`) không hoàn tác được.

**Cấu hình:**

- `.claude/settings.json` → `hooks.PreToolUse`
- `.claude/hooks/guard-bash.sh`: script cho matcher `Bash`
- `.claude/hooks/guard-files.sh`: script cho matcher `Read|Edit|MultiEdit|Write|Grep`
- `.claude/hooks/env-names.sh`: logic nhận diện tên file env, hai script trên dùng chung

**Thực thi:** Claude Code gọi script trước mỗi lần dùng tool; `exit 2` = chặn, stderr được gửi cho agent.

**Kiểm tra:**

- **matcher `Bash`**
  - `rm -rf`, `git push --force`, `git reset --hard`, kể cả khi đứng sau `do`/`then`/`xargs`/`find -exec`/`sudo`/`env`, gọi bằng đường dẫn (`/bin/rm`) hoặc có tuỳ chọn toàn cục (`git -C <dir>`)
  - Bỏ qua lớp 2: `--no-verify`, `git commit -n`, `LEFTHOOK=0`, `LEFTHOOK_EXCLUDE`/`LEFTHOOK_CONFIG`/`LEFTHOOK_BIN`, `lefthook-local.yml`, `.git/hooks`, đổi `core.hooksPath`, `lefthook uninstall`
  - Migrate / push DB (`prisma migrate`, `prisma db push`/`execute`, `drizzle-kit push`/`migrate`) khi DB không phải local (`localhost`, `127.0.0.1`, `[::1]`, `host.docker.internal`). Nếu lệnh không đặt `DATABASE_URL` và môi trường cũng không có, **mọi** file env có `DATABASE_URL` đều phải trỏ về local, vì mỗi tool đọc file khác nhau (Prisma CLI chỉ đọc `.env`). Không tìm thấy `DATABASE_URL` ở đâu thì cũng chặn
  - Lệnh chạm tới `.env*` (ví dụ `cat .env`), không phân biệt hoa thường (`.ENV.local`), kể cả glob ngoài dấu nháy (`.en?.local`, `.e*`) và brace (`{.env.local,}`). Tên như `.envrc` không bị chặn
- **matcher `Read|Edit|MultiEdit|Write|Grep`**
  - Đường dẫn `.env*` (không phân biệt hoa thường, kể cả glob của Grep), trừ file mẫu `.env.example`, `.env.sample`, `.env.template`
  - `Edit`/`MultiEdit`/`Write` vào `.git/hooks/` hoặc `lefthook-local.*` (kể cả `.lefthook-local.*`)

### 1b. Ngay sau khi agent sửa file: `PostToolUse` (1–3 giây)

**Mục đích:** giữ code đúng format và sạch lint ngay trong lúc agent làm việc, để agent tự sửa lỗi trong session thay vì đợi tới lúc commit hoặc CI mới biết.

**Cấu hình:**

- `.claude/settings.json` → `hooks.PostToolUse`, matcher `Edit|MultiEdit|Write`
- `.claude/hooks/format-lint.sh`: script chạy prettier và eslint

**Thực thi:** Claude Code gọi script sau mỗi lần sửa, chỉ trên file vừa sửa. Còn lỗi không tự sửa được → `exit 2`, agent đọc lỗi và sửa tiếp.

**Kiểm tra:**

- `prettier --write --ignore-unknown` (prettier fail, thường do lỗi cú pháp, cũng là `exit 2`)
- `eslint --fix --max-warnings 0` (chỉ file JS/TS)

---

## Lớp 2 · Git hooks

_Chạy trên máy dev, áp dụng cho cả người lẫn agent._

### 2a. `git commit`: `pre-commit` (< 30 giây)

**Mục đích:** chặn code chưa format, lỗi lint và secret trước khi vào lịch sử git. Secret đã commit và push thì coi như đã lộ, phải rotate key.

**Cấu hình:**

- `lefthook.yml` → `pre-commit`
- `package.json` → `"prepare": "lefthook install"`: cài hook, tự chạy khi `pnpm install`
- Máy dev cần cài gitleaks: `brew install gitleaks`

**Thực thi:** Lefthook, chỉ trên file đã stage (`{staged_files}`), file được sửa tự stage lại (`stage_fixed: true`). Các job chạy lần lượt, vì prettier và eslint cùng ghi vào một file.

**Kiểm tra:**

- **Chất lượng**
  - `prettier --write --ignore-unknown`
  - `eslint --fix --max-warnings 0` (chỉ file JS/TS)
- **Bảo mật**
  - `gitleaks git --pre-commit --staged --redact` (máy chưa cài gitleaks → commit bị chặn kèm hướng dẫn cài)

### 2b. `git push`: `pre-push` (< 2 phút)

**Mục đích:** bắt lỗi type và test hỏng trước khi code rời máy local, tránh phải đợi CI vài phút mới phát hiện.

**Cấu hình:**

- `lefthook.yml` → `pre-push`

**Thực thi:** Lefthook, trên toàn project.

**Kiểm tra:**

- `pnpm typecheck` (`next typegen && tsc --noEmit`, sinh type route trước khi typecheck)
- `pnpm test` (`vitest run`)

---

## Lớp 3 · CI gate

_Chạy trên GitHub Actions runner, khi mở / cập nhật pull request; các job chạy song song (5–10 phút)._

**Mục đích:** kiểm tra đầy đủ trên môi trường sạch, không phụ thuộc máy của ai. Bắt những gì lọt qua local (hook bị tắt, `--no-verify`), các thủ thuật lách check, và lỗ hổng bảo mật.

**Cấu hình:**

- `.github/workflows/ci.yml`: job 3a, 3b, 3c
- `.github/actions/setup/action.yml`: cài pnpm, Node theo `.nvmrc`, dependencies
- `.github/workflows/claude-review.yml`: job 3d, tách workflow riêng để tắt được khi cần tiết kiệm token mà không ảnh hưởng `ci.yml`
- Secret `ANTHROPIC_API_KEY` cho job 3d

**Thực thi:** GitHub Actions; mỗi job là một status check trên PR, tên check = tên job. Action được pin theo commit SHA đầy đủ (tag ghi trong comment) của bản phát hành ít nhất 21 ngày, vì tag có thể bị dời sang commit khác.

**Kiểm tra:**

- **3a · Chất lượng, toàn repo**
  - `lint`: `pnpm format:check` + `pnpm lint --max-warnings 0`
  - `typecheck`: `pnpm typecheck`
  - `test`: `pnpm test`
  - `build`: `pnpm build`
- **3b · Chống lách check** (chỉ chạy trên PR)
  - `suppressions`: `scripts/check-suppressions.sh` fail nếu các dòng _được thêm_ so với nhánh base có `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`, `nosemgrep`, `gitleaks:allow`. Bỏ qua file `.md`, `.claude/hooks/`, chính script và file test của nó (`scripts/check-suppressions*`). Lỗi hiện thành annotation trên diff của PR. Comment cấu hình rule inline (`/* eslint rule: "off" */`) thì do ESLint chặn tận gốc: `eslint.config.mjs` đặt `noInlineConfig: true` nên job `lint` fail
- **3c · Bảo mật**
  - `gitleaks`: CLI gitleaks (kiểm sha256 ghim sẵn trong workflow khi tải) quét các commit của PR; push vào `main` thì quét toàn bộ lịch sử
  - `semgrep`: image `semgrep/semgrep` ghim theo digest, `semgrep scan --error` với `p/typescript`, `p/react`, `p/owasp-top-ten`
  - `dependency-review` (chỉ chạy trên PR): `actions/dependency-review-action`, `fail-on-severity: high`
- **3d · Reviewer agent**
  - `claude-review`: `anthropics/claude-code-action` (model `claude-sonnet-5-5`, tối đa 15 lượt) review toàn bộ diff của PR theo quy tắc trong `CLAUDE.md`
  - Chỉ-đọc: không có `Edit`/`Write`; Bash chỉ được `git diff` và `gh pr comment`. Không có `gh pr view` để comment của người ngoài trên PR (repo public) không vào context của agent
  - Checkout đúng commit head của PR (`head.sha`), diff bằng `git diff origin/<base>...HEAD`, nên file agent đọc, diff và SHA trong comment là của cùng một commit
  - Chỉ nêu lỗi nghiêm trọng (blocking): bug làm sai hoặc crash, lỗ hổng bảo mật, mất dữ liệu, vi phạm quy tắc `CLAUDE.md` mà lint/type/test/scanner không bắt được. Mỗi lỗi có `file:line`, lý do và kịch bản cụ thể. Không comment format, style, gợi ý cải thiện
  - Mỗi commit được review có **một comment mới** (dòng đầu: `Review cho commit <7 ký tự đầu của SHA>`); không có lỗi thì ghi "Không có lỗi nghiêm trọng." Comment thường, không phải thread inline, nên không bị rule resolve conversation chặn merge
  - Không chặn merge vì nội dung review: job xanh khi review xong, người review quyết định. Required check chỉ đảm bảo mỗi PR đã qua reviewer agent
  - Push commit mới khi review cũ chưa xong → review cũ bị hủy (`concurrency`), chỉ commit mới nhất được review
  - Bỏ qua (check tính là đạt): PR draft (review khi chuyển ready), PR từ fork và PR của bot (không có secret)

---

## Lớp 4 · Merge policy

_Chạy trên GitHub server, khi merge PR vào `main` và mọi lần push vào `main` (tức thì)._

**Mục đích:** đảm bảo không có code nào vào `main` mà chưa qua CI xanh và review của người. Lớp này biến kết quả của lớp 3, vốn chỉ báo lỗi, thành điều kiện bắt buộc để merge.

**Cấu hình:**

- `.github/rulesets/main-protection.json`: ruleset `main-protection`, owner áp dụng lên GitHub (xem bên dưới)
- `.github/CODEOWNERS`: các file "luật chơi" và owner của chúng

**Thực thi:** GitHub; điều kiện chưa đủ → nút Merge bị khóa, push thẳng vào `main` bị từ chối.

**Kiểm tra:**

- **Điều kiện để merge**
  - Bắt buộc qua pull request
  - Required status checks: 9 check của lớp 3 xanh, nguồn **GitHub Actions**, tên phải khớp tên job: `lint`, `typecheck`, `test`, `build`, `suppressions`, `gitleaks`, `semgrep`, `dependency-review`, `claude-review`
  - Nhánh phải cập nhật theo `main`
  - Approval: **1**, từ người khác người push cuối cùng. Push mới vào PR làm mất approval cũ, phải duyệt lại
  - Code owner duyệt các file trong `.github/CODEOWNERS`. Có hai owner (`@st-huynguyen`, `@bd-huynguyen`) để người này duyệt thay đổi của người kia, vì tác giả không tự approve PR của mình được
  - Mọi conversation trên PR phải được resolve
- **Bảo vệ nhánh**
  - Áp dụng cho nhánh mặc định
  - Cấm force push, cấm xóa nhánh
  - Danh sách bypass để trống
  - Không bật **Restrict updates** (rule này chặn cả việc merge PR)

### Áp dụng ruleset (owner làm)

`.github/rulesets/main-protection.json` là nguồn sự thật, nhưng GitHub không tự đọc file này, owner phải áp dụng. Không sửa ruleset trực tiếp trên UI mà không cập nhật file, nếu không file và cấu hình thật sẽ lệch nhau.

- Điều kiện trước: repo có secret `ANTHROPIC_API_KEY` (Settings → Secrets and variables → Actions). Thiếu secret thì job `claude-review` fail, và vì đây là check bắt buộc nên mọi PR (trừ draft, fork, bot) bị chặn merge
- Tạo lần đầu: Settings → Rules → Rulesets → New ruleset → **Import a ruleset** → chọn file, hoặc `gh api -X POST repos/<owner>/<repo>/rulesets --input .github/rulesets/main-protection.json`
- Cập nhật: sửa file qua PR, merge, rồi `gh api -X PUT repos/<owner>/<repo>/rulesets/<id> --input .github/rulesets/main-protection.json` (lấy `<id>` bằng `gh api repos/<owner>/<repo>/rulesets`)

---

## Thuật ngữ

| Thuật ngữ             | Giải thích                                                                                                                                                |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hook của Claude Code  | Lệnh shell mà Claude Code tự gọi ở một thời điểm cố định trong session (ví dụ trước hoặc sau khi agent dùng tool). Khai báo trong `.claude/settings.json` |
| `PreToolUse`          | Hook chạy **trước** khi agent dùng một tool (Bash, Read, Edit...). Script trả `exit 2` thì tool không được chạy                                           |
| `PostToolUse`         | Hook chạy **sau** khi tool chạy xong. Không hoàn tác được thao tác, chỉ báo lỗi để agent sửa tiếp                                                         |
| Git hook              | Script git tự chạy ở một bước như commit hoặc push. Script lỗi thì bước đó bị hủy                                                                         |
| Lefthook              | Tool quản lý git hook bằng file `lefthook.yml` commit trong repo, để mọi máy có cùng hook ngay sau `pnpm install` thay vì tự chép vào `.git/hooks`        |
| `pre-commit`          | Git hook chạy khi `git commit`, trước khi commit được tạo                                                                                                 |
| `pre-push`            | Git hook chạy khi `git push`, trước khi code được gửi lên remote                                                                                          |
| Prettier              | Tool tự format code (thụt lề, dấu nháy, xuống dòng) theo một chuẩn chung                                                                                  |
| ESLint                | Tool lint: tìm lỗi và pattern xấu trong code JS/TS. `--max-warnings 0` coi warning như lỗi                                                                |
| gitleaks              | Tool quét secret (API key, token, mật khẩu) trong code và lịch sử git                                                                                     |
| `next typegen`        | Lệnh Next.js sinh type cho route (`PageProps`, `LayoutProps`) để `tsc` kiểm tra được                                                                      |
| Vitest                | Test runner chạy file `*.test.ts`                                                                                                                         |
| GitHub Actions        | Hệ thống CI của GitHub. Mỗi workflow (file YAML trong `.github/workflows/`) gồm nhiều job chạy trên máy ảo (runner)                                       |
| Status check          | Kết quả đạt hoặc không đạt của một job, hiện trên PR                                                                                                      |
| Required status check | Status check bắt buộc phải xanh thì PR mới merge được. Danh sách nằm trong ruleset                                                                        |
| suppressions          | Job 3b: chặn PR thêm comment tắt kiểm tra (`eslint-disable`, `@ts-ignore`, `nosemgrep`...), vì đó là cách lách lint, type hoặc scanner thay vì sửa lỗi    |
| semgrep               | Tool phân tích tĩnh: quét code theo bộ rule để tìm lỗ hổng bảo mật và pattern nguy hiểm                                                                   |
| dependency-review     | Action so sánh dependency trước và sau PR, fail nếu PR thêm package có lỗ hổng từ mức `high` trở lên                                                      |
| claude-code-action    | GitHub Action chạy Claude Code bên trong workflow. Ở đây dùng làm reviewer agent (job 3d)                                                                 |
| `concurrency`         | Cấu hình GitHub Actions gom các lần chạy cùng nhóm. Lần chạy mới hủy lần chạy cũ còn dang dở                                                              |
| Ruleset               | Bộ quy tắc GitHub áp lên nhánh (ở đây là `main`): bắt qua PR, required checks, approval, cấm force push...                                                |
| `CODEOWNERS`          | File gán owner cho từng đường dẫn. PR sửa các file đó cần một owner approve                                                                               |

---

## Khi agent tự sửa luật chơi để lách check

**Nguyên tắc:** mọi thay đổi làm yếu một check đều phải có người khác duyệt. Agent không thể âm thầm làm yếu check.

- **Tắt check ngay trong code** → CI tự chặn, không cần người:
  - Job `suppressions` fail khi PR thêm `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`, `nosemgrep`, `gitleaks:allow`
  - ESLint bật `noInlineConfig`, nên comment cấu hình rule inline (`/* eslint rule: "off" */`) không có tác dụng và làm job `lint` fail
- **Nới lỏng config hoặc sửa chính các check** → bắt buộc code owner duyệt:
  - File "luật chơi" nằm trong `CODEOWNERS`: config lint/type/format/test, `package.json`, file bỏ qua của scanner, hook, CI, scripts, `CLAUDE.md`, `AGENTS.md` và tài liệu này
  - Ruleset bắt code owner approve, push mới làm mất approval cũ, tác giả không tự approve PR của mình
  - Agent vẫn sửa được các file này ở local, nhưng không merge được vào `main` khi code owner chưa duyệt
- **File thường** → quy trình bình thường: đủ required checks xanh và 1 approval, không cần code owner

**Điều kiện để giải pháp kín:**

- Agent không có thông tin đăng nhập của người duyệt
- Agent không có token admin, vì admin sửa hoặc tắt được ruleset
- Người duyệt đọc kỹ diff của file config, không approve cho có
