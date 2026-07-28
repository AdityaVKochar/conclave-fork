import { describe, expect, it, vi } from "vitest";
import type { Socket } from "socket.io";
import type { Room } from "../config/classes/Room.js";
import type { ConnectionContext } from "../server/socket/context.js";
import { registerWebinarInteractionHandlers } from "../server/socket/handlers/webinarInteractionHandlers.js";
import type { SfuState } from "../server/state.js";
import type { WebinarRoomConfig } from "../server/webinar.js";

type SocketHandler = (...args: never[]) => unknown;

describe("webinar interaction handlers", () => {
  it("rejects attendee upvotes while Q&A is disabled", () => {
    const handlers = new Map<string, SocketHandler>();
    const socket = {
      on: vi.fn((event: string, handler: SocketHandler) => {
        handlers.set(event, handler);
        return socket;
      }),
      emit: vi.fn(),
      connected: true,
    } as unknown as Socket;
    const toggleWebinarQuestionUpvote = vi.fn();
    const room = {
      id: "room",
      channelId: "instance:room",
      toggleWebinarQuestionUpvote,
    } as unknown as Room;
    const webinarConfig = {
      enabled: true,
      qaEnabled: false,
    } as WebinarRoomConfig;
    const state = {
      webinarConfigs: new Map([[room.channelId, webinarConfig]]),
    } as unknown as SfuState;
    const context = {
      socket,
      io: {} as ConnectionContext["io"],
      state,
      currentRoom: room,
      currentClient: { id: "attendee", isWebinarAttendee: true },
      pendingRoomId: null,
      pendingRoomChannelId: null,
      pendingUserKey: null,
      currentUserKey: null,
      activeConclaveAnswers: new Map(),
      adminHandlersRegistered: false,
    } as unknown as ConnectionContext;

    registerWebinarInteractionHandlers(context);
    const upvote = handlers.get("webinar:qa:upvote") as unknown as (
      data: { id: string },
      callback: (response: { error?: string }) => void,
    ) => void;
    let response: { error?: string } | undefined;
    upvote({ id: "question-1" }, (value) => {
      response = value;
    });

    expect(response).toEqual({
      error: "Q&A is turned off for this webinar",
    });
    expect(toggleWebinarQuestionUpvote).not.toHaveBeenCalled();
  });
});
