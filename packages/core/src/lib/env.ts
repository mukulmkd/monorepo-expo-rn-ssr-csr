export type Env = {
  API_BASE_URL: string;
};

export function getEnv(): Env {
  return {
    API_BASE_URL: process.env.API_BASE_URL || "",
  };
}
