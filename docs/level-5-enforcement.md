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

|              |                                                                                                                                                |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mục đích** | Chặn hành động nguy hiểm hoặc truy cập secret _trước khi_ nó xảy ra, vì nhiều hành động (xóa file, force push, đọc `.env`) không hoàn tác được |
| **Cấu hình** | `.claude/settings.json` → `hooks.PreToolUse`<br>Script: `.claude/hooks/guard-bash.sh`, `.claude/hooks/guard-files.sh`                          |
| **Thực thi** | Claude Code gọi script; `exit 2` = chặn, stderr được gửi cho agent                                                                             |

**Kiểm tra:**

- **matcher `Bash`**
  - `rm -rf`, `git push --force`, `git reset --hard`, kể cả khi đứng sau `do`/`then`/`xargs`/`find -exec`/`sudo`/`env`, gọi bằng đường dẫn (`/bin/rm`) hoặc có tuỳ chọn toàn cục (`git -C <dir>`)
  - Bỏ qua lớp 2: `--no-verify`, `git commit -n`, `LEFTHOOK=0`, `LEFTHOOK_EXCLUDE`/`LEFTHOOK_CONFIG`/`LEFTHOOK_BIN`, `lefthook-local.yml`, `.git/hooks`, đổi `core.hooksPath`, `lefthook uninstall`
  - Migrate / push DB khi không phải môi trường local. Nếu lệnh không đặt `DATABASE_URL` và môi trường cũng không có, **mọi** file env có `DATABASE_URL` đều phải trỏ về local, vì mỗi tool đọc file khác nhau (Prisma CLI chỉ đọc `.env`)
  - Lệnh chạm tới `.env*` (ví dụ `cat .env`), không phân biệt hoa thường (`.ENV.local`), kể cả glob ngoài dấu nháy (`.en?.local`, `.e*`) và brace (`{.env.local,}`). Tên như `.envrc` không bị chặn
- **matcher `Read|Edit|MultiEdit|Write|Grep`**
  - Đường dẫn `.env*` (không phân biệt hoa thường, kể cả glob của Grep), trừ `.env.example`
  - `Edit`/`Write` vào `.git/hooks/` hoặc `lefthook-local.yml`
- Logic nhận diện tên file env dùng chung ở `.claude/hooks/env-names.sh`

### 1b. Ngay sau khi agent sửa file: `PostToolUse` (1–3 giây)

|              |                                                                                                                                                |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mục đích** | Giữ code đúng format và sạch lint ngay trong lúc agent làm việc, để agent tự sửa lỗi trong session thay vì đợi tới lúc commit hoặc CI mới biết |
| **Cấu hình** | `.claude/settings.json` → `hooks.PostToolUse`, matcher `Edit\|MultiEdit\|Write`<br>Script: `.claude/hooks/format-lint.sh`                      |
| **Thực thi** | `prettier --write <file>` → `eslint --fix --max-warnings 0 <file>` (chỉ file JS/TS)                                                            |

**Kiểm tra:**

- Chỉ chạy trên file vừa sửa.
- Lỗi lint không tự sửa được → `exit 2`, agent đọc lỗi và sửa tiếp.

---

## Lớp 2 · Git hooks

_Chạy trên máy dev._

**Mục đích:** chặn lỗi trước khi code vào lịch sử git và trước khi code rời máy local, áp dụng cho cả người lẫn agent. `pre-commit` chặn code chưa format, lỗi lint và secret (secret đã commit và push thì coi như đã lộ, phải rotate key). `pre-push` bắt lỗi type và test hỏng, tránh phải đợi CI vài phút mới phát hiện.

### 2a. `git commit`: `pre-commit` (< 30 giây)

|              |                                                                                                                                                                       |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cấu hình** | `lefthook.yml` → `pre-commit`<br>Cài hook: `package.json` → `"prepare": "lefthook install"` (tự chạy khi `pnpm install`)<br>Yêu cầu trên máy: `brew install gitleaks` |
| **Thực thi** | Lefthook, chỉ trên `{staged_files}`, `stage_fixed: true`. Các job chạy lần lượt (prettier và eslint cùng ghi vào một file nên không chạy song song)                   |

**Kiểm tra:**

- **Chất lượng**
  - `prettier --write --ignore-unknown`
  - `eslint --fix --max-warnings 0` (chỉ file JS/TS)
- **Bảo mật**
  - `gitleaks git --pre-commit --staged --redact` (máy chưa cài gitleaks → commit bị chặn kèm hướng dẫn cài)

### 2b. `git push`: `pre-push` (< 2 phút)

|              |                             |
| ------------ | --------------------------- |
| **Cấu hình** | `lefthook.yml` → `pre-push` |
| **Thực thi** | Lefthook, trên toàn project |

**Kiểm tra:**

- `pnpm typecheck` (`next typegen && tsc --noEmit`, sinh type route trước khi typecheck)
- `pnpm test` (`vitest run`)

---

## Lớp 3 · CI gate

_Chạy trên GitHub Actions runner._

### Event `pull_request` → các job chạy song song (5–10 phút)

|              |                                                                                                                                                                                                                                        |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mục đích** | Kiểm tra đầy đủ trên môi trường sạch, không phụ thuộc máy của ai. Bắt những gì lọt qua local (hook bị tắt, `--no-verify`), các thủ thuật lách check, và lỗ hổng bảo mật                                                                |
| **Cấu hình** | `.github/workflows/ci.yml` (job 3a, 3b, 3c)<br>`.github/actions/setup/action.yml` (cài pnpm, Node theo `.nvmrc`, dependencies)<br>`.github/workflows/claude-review.yml` (job 3d, làm ở PR sau)<br>Secret: `ANTHROPIC_API_KEY` (cho 3d) |
| **Thực thi** | GitHub Actions; mỗi job → một status check trên PR. Action được pin theo commit SHA đầy đủ (tag ghi trong comment) của bản phát hành ít nhất 21 ngày, vì tag có thể bị dời sang commit khác                                            |

**Kiểm tra** (tên job = tên status check):

- **3a · Chất lượng, toàn repo**
  - `lint`: `pnpm format:check` + `pnpm lint --max-warnings 0`
  - `typecheck`: `pnpm typecheck`
  - `test`: `pnpm test`
  - `build`: `pnpm build`
- **3b · Chống lách check** (chỉ chạy trên PR)
  - `suppressions`: `scripts/check-suppressions.sh` fail nếu các dòng _được thêm_ so với nhánh base có `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck`, `nosemgrep`, `gitleaks:allow`. Bỏ qua file `.md`, `.claude/hooks/` và chính script. Lỗi hiện thành annotation trên diff của PR. Comment cấu hình rule inline (`/* eslint rule: "off" */`) thì do ESLint chặn tận gốc: `eslint.config.mjs` đặt `noInlineConfig: true` nên job `lint` fail
- **3c · Bảo mật**
  - `gitleaks`: CLI gitleaks (kiểm sha256 ghim sẵn trong workflow khi tải) quét các commit của PR; push vào `main` thì quét toàn bộ lịch sử
  - `semgrep`: image `semgrep/semgrep` ghim theo digest, `semgrep scan --error` với `p/typescript`, `p/react`, `p/owasp-top-ten`
  - `dependency-review` (chỉ chạy trên PR): `actions/dependency-review-action`, `fail-on-severity: high`
- **3d · Reviewer agent (tốn token, làm ở PR sau)**
  - `anthropics/claude-code-action@v1`, chỉ-đọc, chỉ comment blocking

> Job 3d nằm trong workflow riêng để có thể bật sau cùng hoặc tắt khi cần tiết kiệm, không ảnh hưởng `ci.yml`.

> Ở lớp 3, check đỏ chỉ báo lỗi, chưa chặn được merge. Lớp 4 mới biến các check này thành điều kiện bắt buộc.

---

## Lớp 4 · Merge policy

_Chạy trên GitHub server._

### Khi merge PR vào `main`, và mọi lần push vào `main` (tức thì)

|              |                                                                                                                                                                                                                          |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Mục đích** | Đảm bảo không có code nào vào `main` mà chưa qua CI xanh và review của người. Lớp này biến kết quả của lớp 3 thành điều kiện bắt buộc để merge                                                                           |
| **Cấu hình** | Ruleset `main-protection`: định nghĩa trong `.github/rulesets/main-protection.json`, owner áp dụng lên GitHub (file trong repo tự nó không có hiệu lực)<br>`.github/CODEOWNERS`: các file "luật chơi" và owner của chúng |
| **Thực thi** | GitHub; điều kiện chưa đủ → nút Merge bị khóa                                                                                                                                                                            |

**Kiểm tra:**

- **Điều kiện để merge**
  - Bắt buộc qua pull request
  - Required status checks: 8 job của lớp 3 xanh (3d thêm vào khi có)
  - Nhánh phải cập nhật theo `main`
  - Approval: **0** khi repo chỉ có một người, đặt **1** khi có thêm người có quyền write
  - Code owner duyệt các file trong `.github/CODEOWNERS`: **tạm tắt** khi chỉ có một owner, vì tác giả không tự approve PR của mình được
- **Bảo vệ nhánh**
  - Cấm force push, cấm xóa nhánh
  - Danh sách bypass để trống

### Áp dụng ruleset (owner làm)

File `.github/rulesets/main-protection.json` là nguồn sự thật. GitHub không tự đọc file này, owner phải áp dụng:

- Tạo lần đầu: Settings → Rules → Rulesets → New ruleset → **Import a ruleset** → chọn file, hoặc `gh api -X POST repos/<owner>/<repo>/rulesets --input .github/rulesets/main-protection.json`
- Cập nhật: sửa file qua PR, merge, rồi `gh api -X PUT repos/<owner>/<repo>/rulesets/<id> --input .github/rulesets/main-protection.json` (lấy `<id>` bằng `gh api repos/<owner>/<repo>/rulesets`)
- Không sửa ruleset trực tiếp trên UI mà không cập nhật file, nếu không file và cấu hình thật sẽ lệch nhau

### Checklist ruleset `main-protection` (nội dung của file JSON)

- **Enforcement status:** Active · **Bypass list:** để trống
- **Target branches:** Add target → _Include default branch_
- ✓ **Restrict deletions**
- ✓ **Block force pushes**
- ✓ **Require a pull request before merging**
  - Required approvals: **0**
  - ✓ Dismiss stale pull request approvals when new commits are pushed
  - ☐ Require review from Code Owners (bật khi có owner thứ hai)
  - ✓ Require conversation resolution before merging
- ✓ **Require status checks to pass**
  - ✓ Require branches to be up to date before merging
  - 8 check, nguồn **GitHub Actions**, tên phải khớp tên job: `lint`, `typecheck`, `test`, `build`, `suppressions`, `gitleaks`, `semgrep`, `dependency-review`
- Để trống **Restrict updates** (rule này chặn cả việc merge PR)

### Khi nào đổi cấu hình

| Tình huống                           | Đổi gì                                                                                         |
| ------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Có thêm người có quyền write         | Required approvals → 1                                                                         |
| `CODEOWNERS` có từ hai owner trở lên | Bật _Require review from Code Owners_ và _Require approval of the most recent reviewable push_ |
| Thêm hoặc đổi tên job trong `ci.yml` | Cập nhật danh sách required checks cho khớp tên, nếu không PR sẽ chờ mãi một check không chạy  |
| Có job 3d (reviewer agent)           | Thêm check của job đó vào danh sách                                                            |

### Kiểm chứng lớp 4 đang hoạt động

| Kiểm tra                         | Lệnh hoặc chỗ xem                                                                       | Kỳ vọng                                                                                                       |
| -------------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Rule có hiệu lực trên `main`     | `gh api repos/<owner>/<repo>/rules/branches/main --jq '.[].type'`                       | `deletion`, `non_fast_forward`, `pull_request`, `required_status_checks`                                      |
| Đủ 8 check bắt buộc              | Như trên, lọc `required_status_checks` → `.parameters.required_status_checks[].context` | Đúng 8 tên                                                                                                    |
| PR đủ điều kiện thì merge được   | `gh pr view <n> --json mergeStateStatus` (PR không phải draft, 8 check xanh)            | `CLEAN`                                                                                                       |
| PR có check đỏ bị chặn           | `gh pr view <n> --json mergeStateStatus` (PR không phải draft, có check bắt buộc đỏ)    | `BLOCKED`, trên UI hiện _"Merging is blocked"_                                                                |
| `CODEOWNERS` hợp lệ              | `gh api repos/<owner>/<repo>/codeowners/errors`                                         | `{"errors":[]}`                                                                                               |
| Push thẳng vào `main` bị từ chối | `git push origin HEAD:main` (chỉ thử khi các mục trên đã đạt)                           | `GH013: Repository rule violations found for refs/heads/main` … _Changes must be made through a pull request_ |

> Admin vẫn có thể sửa hoặc tắt ruleset. Mọi thay đổi ruleset nên được báo cho team và cập nhật lại checklist này.

> Lưu ý: private repo trên gói GitHub Free không dùng được rulesets. Cần gói Team hoặc Enterprise.
