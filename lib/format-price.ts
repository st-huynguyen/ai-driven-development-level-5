export function formatPrice(amount: number, currency = "USD"): string {
  if (!Number.isFinite(amount)) {
    throw new RangeError(`Invalid amount: ${amount}`);
  }
  return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(
    amount,
  );
}
