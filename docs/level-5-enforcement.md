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
  - `rm -rf`, `git push --force`, `git reset --hard`
  - Migrate / push DB khi không phải môi trường local
  - Lệnh chạm tới `.env*` (ví dụ `cat .env`)
- **matcher `Read|Edit|MultiEdit|Write|Grep`**
  - Đường dẫn `.env*`, trừ `.env.example`

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

|              |                                                                                                                |
| ------------ | -------------------------------------------------------------------------------------------------------------- |
| **Cấu hình** | `lefthook.yml` → `pre-commit` (`parallel: true`)<br>Cài hook: `package.json` → `"prepare": "lefthook install"` |
| **Thực thi** | Lefthook, chỉ trên `{staged_files}`, `stage_fixed: true`                                                       |

**Kiểm tra:**

- **Chất lượng**
  - `prettier --write`
  - `eslint --fix`
- **Bảo mật**
  - `gitleaks git --pre-commit --staged`

### 2b. `git push`: `pre-push` (< 2 phút)

|              |                             |
| ------------ | --------------------------- |
| **Cấu hình** | `lefthook.yml` → `pre-push` |
| **Thực thi** | Lefthook, trên toàn project |

**Kiểm tra:**

- `tsc --noEmit`
- `vitest run`

---

## Lớp 3 · CI gate

_Chạy trên GitHub Actions runner._

### Event `pull_request` → các job chạy song song (5–10 phút)

|              |                                                                                                                                                                         |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mục đích** | Kiểm tra đầy đủ trên môi trường sạch, không phụ thuộc máy của ai. Bắt những gì lọt qua local (hook bị tắt, `--no-verify`), các thủ thuật lách check, và lỗ hổng bảo mật |
| **Cấu hình** | `.github/workflows/ci.yml` (job 3a, 3b, 3c)<br>`.github/workflows/claude-review.yml` (job 3d)<br>Secret: `ANTHROPIC_API_KEY`                                            |
| **Thực thi** | GitHub Actions; mỗi job → một status check trên PR                                                                                                                      |

**Kiểm tra:**

- **3a · Chất lượng, toàn repo**
  - `prettier --check .`
  - `eslint . --max-warnings 0`
  - `tsc --noEmit` · `vitest run` · `next build`
- **3b · Chống lách check**
  - Script `scripts/check-suppressions.sh`: fail nếu diff thêm `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `nosemgrep`
- **3c · Bảo mật**
  - Secret: `gitleaks`
  - SAST: `semgrep scan --error`
  - Dependency: `actions/dependency-review-action`
- **3d · Reviewer agent (tốn token)**
  - `anthropics/claude-code-action@v1`, chỉ-đọc, chỉ comment blocking

> Job 3d nằm trong workflow riêng để có thể bật sau cùng hoặc tắt khi cần tiết kiệm, không ảnh hưởng `ci.yml`.

---

## Lớp 4 · Merge policy

_Chạy trên GitHub server._

### Khi merge PR vào `main`, và mọi lần push vào `main` (tức thì)

|              |                                                                                                                                                |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mục đích** | Đảm bảo không có code nào vào `main` mà chưa qua CI xanh và review của người. Lớp này biến kết quả của lớp 3 thành điều kiện bắt buộc để merge |
| **Cấu hình** | GitHub → Settings → Rules → Rulesets (target: `main`)<br>`.github/CODEOWNERS`                                                                  |
| **Thực thi** | GitHub; điều kiện chưa đủ → nút Merge bị khóa                                                                                                  |

**Kiểm tra:**

- **Điều kiện để merge**
  - Bắt buộc qua pull request
  - Required status checks: các job 3a–3d xanh
  - Nhánh phải cập nhật theo `main`
  - Ít nhất 1 approval
  - Code owner duyệt file config (cần cả file `CODEOWNERS` và bật "Require review from Code Owners" trong ruleset)
- **Bảo vệ nhánh**
  - Cấm force push, cấm xóa nhánh
  - Danh sách bypass để trống

> Lưu ý: private repo trên gói GitHub Free không dùng được rulesets. Cần gói Team hoặc Enterprise.
