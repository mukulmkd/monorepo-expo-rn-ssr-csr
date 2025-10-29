export type ApiClientConfig = {
  baseUrl: string;
  headers?: Record<string, string>;
};

export function createApiClient(config: ApiClientConfig) {
  async function request<T>(path: string, init?: RequestInit): Promise<T> {
    const res = await fetch(config.baseUrl + path, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        ...(config.headers || {}),
        ...(init?.headers || {}),
      },
    });
    if (!res.ok) throw new Error(`API error ${res.status}`);
    return (await res.json()) as T;
  }
  return { request };
}
