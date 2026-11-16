// CI smoke test (canary for the `semgrep` job): known-unsafe code on purpose.
// Do not merge.
import { exec } from "node:child_process";

// --- Must be caught: the `semgrep` job has to fail on this. ---

type Req = { query: { name: string } };
type Res = { send(body: string): void };

// XSS: user input written straight into the response
// (rule: javascript.express.security.audit.xss.direct-response-write).
export function greet(req: Req, res: Res) {
  res.send("Hello " + req.query.name);
}

// --- Known blind spots: unsafe, but p/typescript, p/react and p/owasp-top-ten
// --- do not report them (checked locally with semgrep 1.182.0).

// Command injection: input interpolated into a shell command.
export function listUploads(folder: string) {
  exec(`ls -la ${folder}`, (error, stdout) => {
    console.log(error ?? stdout);
  });
}

// XSS: raw HTML from the caller rendered without sanitizing.
export function UnsafeComment({ html }: { html: string }) {
  return <div dangerouslySetInnerHTML={{ __html: html }} />;
}

// Code injection: evaluates a string coming from outside (only p/default reports it).
export function runFormula(formula: string): unknown {
  return eval(formula);
}
