import { describe, expect, it } from "vitest";
import { formatPrice } from "@/lib/format-price";

describe("formatPrice", () => {
  it("formats USD by default", () => {
    expect(formatPrice(1234.5)).toBe("$1,234.50");
  });

  it("formats another currency", () => {
    expect(formatPrice(10, "EUR")).toBe("€10.00");
  });

  it("rejects non-finite amounts", () => {
    expect(() => formatPrice(Number.NaN)).toThrow(RangeError);
  });
});
