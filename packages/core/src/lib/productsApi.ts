export type Product = { id: string; name: string; price: number };

function mapDummyJsonProducts(json: any): Product[] {
  if (!json || !Array.isArray(json.products)) return [];
  return json.products.map((p: any) => ({
    id: String(p.id),
    name: String(p.title),
    price: Number(p.price),
  }));
}

export async function getProducts(): Promise<Product[]> {
  const url = "https://dummyjson.com/products?limit=10";
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(String(res.status));
    const json = await res.json();
    return mapDummyJsonProducts(json);
  } catch (_e) {
    return [];
  }
}
