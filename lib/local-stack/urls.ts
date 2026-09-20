/** Regras de fronteira do perfil Docker local. Nunca aceite um host da nuvem. */
const HOSTS_LOCAIS = new Set(["localhost", "supabase.localhost", "[::1]"]);

function ipv4Loopback(host: string): boolean {
  const parts = host.split(".");
  return (
    parts.length === 4 &&
    parts[0] === "127" &&
    parts.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255)
  );
}

export function urlDoSupabaseEhLocal(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      url.protocol === "http:" &&
      (HOSTS_LOCAIS.has(url.hostname.toLowerCase()) || ipv4Loopback(url.hostname))
    );
  } catch {
    return false;
  }
}

export function exigirUrlLocalDoSupabase(value: string): void {
  if (!urlDoSupabaseEhLocal(value)) {
    throw new Error("O perfil de stack local recusou uma URL do Supabase que nao e local.");
  }
}
