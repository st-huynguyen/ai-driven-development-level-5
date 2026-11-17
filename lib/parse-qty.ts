// CI smoke test: this file silences checks on purpose so the `suppressions` job fails.
// Do not merge.

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function parseQty(input: string | number, options?: any): number {
  // @ts-expect-error quick fix: callers sometimes pass a number
  const text: string = input;
  return Number.parseInt(text, options?.radix ?? 10);
}
