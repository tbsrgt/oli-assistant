"""Faux serveur IMAP en clair sur 127.0.0.1, pour tester ImapClient sans vraie boîte."""
import socket, sys, threading

HDR1 = b"From: =?UTF-8?B?w4lsb2RpZQ==?= <elodie@exemple.fr>\r\nSubject: Devis refonte\r\nMessage-ID: <a1@ex>\r\n\r\n"
TXT1 = b"Bonjour, pouvez-vous me rappeler ?\r\n"
HDR2 = b"From: OVH <facturation@ovh.com>\r\nSubject: Votre facture\r\nMessage-ID: <b2@ovh>\r\nList-Unsubscribe: <mailto:x>\r\n\r\n"
TXT2 = b"Facture disponible.\r\n"

def lit(b): return b"{%d}\r\n" % len(b) + b

def handle(c):
    f = c.makefile("rb")
    c.sendall(b"* OK fake ready\r\n")
    for raw in f:
        line = raw.decode().strip()
        if not line: continue
        tag, cmd = line.split(" ", 1)
        up = cmd.upper()
        if up.startswith("LOGIN"):
            ok = '"bad"' not in cmd
            c.sendall((tag + (" OK logged in\r\n" if ok else " NO [AUTHENTICATIONFAILED] Invalid credentials\r\n")).encode())
        elif up.startswith("AUTHENTICATE XOAUTH2"):
            import base64
            sasl = base64.b64decode(cmd.split(" ")[2]).decode()
            if "auth=Bearer bon-jeton" in sasl:
                c.sendall(tag.encode() + b" OK authenticated\r\n")
            else:
                c.sendall(b"+ eyJzdGF0dXMiOiI0MDAifQ==\r\n")
                f.readline()   # the client answers with an empty line
                c.sendall(tag.encode() + b" NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)\r\n")
        elif up.startswith("STATUS"):
            c.sendall(b'* STATUS "INBOX" (UNSEEN 1)\r\n' + tag.encode() + b" OK\r\n")
        elif up.startswith("SELECT"):
            c.sendall(b"* 2 EXISTS\r\n* OK [UIDVALIDITY 7]\r\n" + tag.encode() + b" OK [READ-WRITE]\r\n")
        elif up.startswith("FETCH"):
            c.sendall(b'* 1 FETCH (UID 41 FLAGS () INTERNALDATE "05-Oct-2026 09:12:00 +0200" BODY[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID LIST-UNSUBSCRIBE)] '
                      + lit(HDR1) + b" BODY[TEXT]<0> " + lit(TXT1) + b")\r\n")
            c.sendall(b'* 2 FETCH (UID 42 FLAGS (\\Seen) INTERNALDATE "04-Oct-2026 18:00:00 +0200" BODY[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID LIST-UNSUBSCRIBE)] '
                      + lit(HDR2) + b" BODY[TEXT]<0> " + lit(TXT2) + b")\r\n")
            c.sendall(tag.encode() + b" OK FETCH done\r\n")
        elif up.startswith("LIST"):
            c.sendall(b'* LIST (\\Noselect) "/" ""\r\n' + tag.encode() + b" OK\r\n")
        elif up.startswith("CREATE") or up.startswith("SUBSCRIBE"):
            c.sendall(tag.encode() + b" NO [ALREADYEXISTS] exists\r\n")
        elif up.startswith("UID MOVE"):
            c.sendall(b"* OK [COPYUID 9 42 300] moved\r\n* 2 EXPUNGE\r\n" + tag.encode() + b" OK Move done\r\n")
        elif up.startswith("LOGOUT"):
            c.sendall(b"* BYE\r\n" + tag.encode() + b" OK\r\n"); break
        else:
            c.sendall(tag.encode() + b" BAD unknown\r\n")
    c.close()

s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0)); s.listen(5)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
while True:
    c, _ = s.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
