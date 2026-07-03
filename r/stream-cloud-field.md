# Clatter investigations/issues/features

1. Stop sending NickServ IDENTIFY with the server/bouncer password on
   001; gate it behind a defcustom and use a separate NickServ
   credential.
2. Stop display-buffer-ing every channel on join/welcome and every DM;
   bury new buffers and rely on the clatter-track mode-line indicator instead.
3. Make the input prompt prefix configurable (%t/%n/%N specifiers or a
   function) instead of hardcoded to clatter--target, with a refresh
   on nick change.
4. Fix left-margin timestamps shifting the prompt right; render left
   timestamps in-text so the prompt stays at column 0.
5. Add a real hide/exclude list for clatter-track (the muted list only
   dims) and stop flagging the *server* buffer as a mention.
6. Persist per-buffer last-read position to disk so reconnect replay
   doesn't re-mark already-read messages as unread activity.
7. Local-echo sent messages immediately instead of waiting on the
   echo-message round-trip (option: opt out of the cap; better:
   optimistic echo + dedup).
8. Anchor URL title previews to a marker at the link's message (like
   image previews) instead of inserting at the live messages marker;
   skip fetches for replayed history.
9. Add a header-line construct (e.g. for the topic) and slim the
   mode-line; decide which fields go where.
10. Self-activate the smart noise filter so away (and other noise)
    from low-SNR nicks is actually hidden by default, instead of
    needing noise in clatter-suppress-messages.
11. Suppress repeated timestamps within the same formatted-time bucket
    so consecutive same-minute messages show one timestamp.