import * as React from "react";
import { getProducts, Product } from "../lib/productsApi";

export function useProducts() {
  const [data, setData] = React.useState<Product[] | null>(null);
  const [loading, setLoading] = React.useState<boolean>(true);
  const [error, setError] = React.useState<Error | null>(null);

  React.useEffect(() => {
    let mounted = true;
    setLoading(true);
    getProducts()
      .then((res) => {
        if (mounted) {
          setData(res);
          setError(null);
        }
      })
      .catch((e) => mounted && setError(e))
      .finally(() => mounted && setLoading(false));
    return () => {
      mounted = false;
    };
  }, []);

  return { data, loading, error } as const;
}
