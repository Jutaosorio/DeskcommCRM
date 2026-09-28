import fs from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { exigirUrlLocalDoSupabase, urlDoSupabaseEhLocal } from "@/lib/local-stack/urls";

const raiz = process.cwd();
const compose = fs.readFileSync(path.join(raiz, "docker-compose.staging-local.yml"), "utf8");
const controle = fs.readFileSync(path.join(raiz, "scripts/stack-local.sh"), "utf8");
const publicEnv = fs.readFileSync(path.join(raiz, "app/public-env-script.tsx"), "utf8");
const envExample = fs.readFileSync(path.join(raiz, ".env.example"), "utf8");

describe("staging local em Docker", () => {
  it("aceita somente destinos HTTP de loopback para o Supabase no perfil local", () => {
    for (const local of [
      "http://supabase.localhost:54321",
      "http://localhost:54321",
      "http://127.0.0.1:54321",
      "http://127.12.0.3:54321",
    ]) {
      expect(urlDoSupabaseEhLocal(local), local).toBe(true);
    }

    for (const remoto of [
      "https://abc.supabase.co",
      "http://127.evil.example.com:54321",
      "http://localhost.evil.example.com:54321",
      "https://supabase.localhost:54321",
    ]) {
      expect(urlDoSupabaseEhLocal(remoto), remoto).toBe(false);
      expect(() => exigirUrlLocalDoSupabase(remoto)).toThrow(/recusou/i);
    }
  });

  it("usa um compose exclusivo, sem env de producao e sem pareamento WhatsApp", () => {
    expect(compose).toContain("name: deskcomm-local");
    expect(compose).toContain("profiles: [\"local\"]");
    expect(compose).toContain("env_file: .env.docker.local");
    expect(compose).toContain('WHATSAPP_RESTART_ALL_SESSIONS: "false"');
    expect(compose).not.toMatch(/supabase\.co|https:\/\//);
    expect(compose).not.toContain("docker-compose.prod.yml");
  });

  it("recusa URL remota antes de colocá-la no bundle do navegador", () => {
    expect(publicEnv).toContain('if (env.NEXT_PUBLIC_LOCAL_STACK === "1")');
    expect(publicEnv).toContain("exigirUrlLocalDoSupabase(env.NEXT_PUBLIC_SUPABASE_URL)");
    expect(publicEnv).toContain("NEXT_PUBLIC_LOCAL_STACK: env.NEXT_PUBLIC_LOCAL_STACK");
    expect(envExample).toContain("NEXT_PUBLIC_LOCAL_STACK=");
  });

  it("interpreta URLs em vez de aceitar globs que parecem loopback", () => {
    expect(controle).toContain("new URL(value)");
    expect(controle).toContain("ipv4Loopback");
    expect(controle).not.toContain("http://127.*");
    expect(controle).toContain("reescrever_db_para_docker");
  });

  it("obriga a confirmacao literal, espera saude e mede todos os servicos locais", () => {
    expect(controle).toContain("--confirm-local-data-loss");
    expect(controle).toContain("--project-name deskcomm-local");
    expect(controle).toContain("--env-file \"$ARQUIVO_ENV\"");
    expect(controle).toContain("supabase stop --no-backup");
    expect(controle).toContain("up --build --detach --wait");
    expect(controle).toContain("for servico in app worker scheduler waha redis");
    expect(controle).toContain("estado_do_servico srh running");
    expect(controle).not.toMatch(/source\s+\.env|\.\s+\.env/);
  });
});
