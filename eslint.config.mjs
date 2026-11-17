import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";
import prettier from "eslint-config-prettier/flat";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Turn off ESLint rules that conflict with Prettier. Keep it after other configs.
  prettier,
  // Comments in source files can't switch rules off or reconfigure them: ESLint
  // ignores them and reports each one, so `--max-warnings 0` fails.
  { linterOptions: { noInlineConfig: true } },
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
]);

export default eslintConfig;
