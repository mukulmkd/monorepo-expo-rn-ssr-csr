export type Product = {
  id: string;
  name: string;
  price: number;
  image?: string;
  description?: string;
  rating?: number;
  brand?: string;
  category?: string;
};

function mapDummyJsonProducts(json: any): Product[] {
  if (!json || !Array.isArray(json.products)) return [];
  return json.products.map((p: any) => ({
    id: String(p.id),
    name: String(p.title),
    price: Number(p.price),
    image: p.thumbnail || p.images?.[0],
    description: p.description,
    rating: p.rating,
    brand: p.brand,
    category: p.category,
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

export async function getProduct(id: string): Promise<Product | null> {
  const url = `https://dummyjson.com/products/${id}`;
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(String(res.status));
    const json = await res.json();
    return {
      id: String(json.id),
      name: String(json.title),
      price: Number(json.price),
      image: json.thumbnail || json.images?.[0],
      description: json.description,
      rating: json.rating,
      brand: json.brand,
      category: json.category,
    };
  } catch (_e) {
    return null;
  }
}
