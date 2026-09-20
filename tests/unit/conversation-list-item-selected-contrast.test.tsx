import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ConversationListItem } from "@/components/inbox/ConversationListItem";
import type { ConversationWithContact } from "@/hooks/inbox/useConversationsRealtime";

const baseConv = {
  id: "c1",
  organization_id: "org-1",
  contact_id: "ct-1",
  channel_session_id: "s1",
  channel: "whatsapp",
  status: "open",
  last_message_at: new Date().toISOString(),
  last_message_preview: "Olá, gostaria de saber mais",
  unread_count_for_assignee: 0,
  created_at: new Date().toISOString(),
  contacts: {
    id: "ct-1",
    display_name: "Andre Teste",
    name: "Andre Teste",
    phone_number: "+5511999998888",
    tags: ["Safe"],
    is_blocked: false,
    is_anonymized: false,
  },
} as unknown as ConversationWithContact;

describe("ConversationListItem - contraste da seleção ativa", () => {
  it("quando selecionado, o texto e os rótulos usam cores escuras para contraste sobre o fundo claro", () => {
    const { container } = render(
      <ConversationListItem
        conversation={baseConv}
        isSelected={true}
        onSelect={() => {}}
      />,
    );

    const nameEl = screen.getByText("Andre Teste");
    expect(nameEl.className).toContain("text-neutral-950");
    expect(nameEl.className).not.toContain("text-text");

    const previewEl = screen.getByText("Olá, gostaria de saber mais");
    expect(previewEl.className).toContain("text-neutral-800");

    const tagEl = screen.getByText("Safe");
    expect(tagEl.className).toContain("text-neutral-900");
  });

  it("quando NÃO selecionado, preserva as classes canônicas do tema", () => {
    render(
      <ConversationListItem
        conversation={baseConv}
        isSelected={false}
        onSelect={() => {}}
      />,
    );

    const nameEl = screen.getByText("Andre Teste");
    expect(nameEl.className).toContain("text-text");
    expect(nameEl.className).not.toContain("text-neutral-950");

    const previewEl = screen.getByText("Olá, gostaria de saber mais");
    expect(previewEl.className).toContain("text-text-muted");
  });
});
