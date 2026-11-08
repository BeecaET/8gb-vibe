"""Stage 1 acceptance harness: real 8gbvibe-mcp processes, temp VIBE_AGENTS_DIR, fake heavy jobs. Stops only its own children."""
import json, os, subprocess, sys, tempfile, threading, time, shutil, signal

BIN = sys.argv[1]
which = sys.argv[2:] or ["2", "10", "11", "12", "17"]
results = {}

class MCP:
    def __init__(self, d, name):
        env = dict(os.environ, VIBE_AGENTS_DIR=d)
        self.p = subprocess.Popen([BIN], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env, text=True, bufsize=1)
        self.n = 0; self.name = name
        self.call_raw("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": name, "version": "0"}})
    def call_raw(self, method, params):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params}) + "\n"); self.p.stdin.flush()
        while True:
            line = self.p.stdout.readline()
            if not line: raise RuntimeError("MCP exited")
            m = json.loads(line)
            if m.get("id") == self.n: return m
    def tool(self, name, **args):
        r = self.call_raw("tools/call", {"name": name, "arguments": args})["result"]
        t = r["content"][0]["text"]
        try: return json.loads(t)
        except Exception: return {"_text": t, "_error": r.get("isError", False)}
    def kill(self):
        if self.p.poll() is None: self.p.kill(); self.p.wait()

def tmp():
    return tempfile.mkdtemp(prefix="8gb-harness-")

def t2():
    ok = 0; detail = []
    for i in range(20):
        d = tmp(); a, b = MCP(d, "A"), MCP(d, "B")
        a.tool("register_agent", tool="Claude Code", project=f"p{i}"); b.tool("register_agent", tool="Codex CLI", project=f"q{i}")
        out = {}
        bar = threading.Barrier(2)
        def go(m, k):
            bar.wait(); out[k] = m.tool("acquire_slot", kind="gradle")["slot"]["status"]
        th = [threading.Thread(target=go, args=(a, "a")), threading.Thread(target=go, args=(b, "b"))]
        [x.start() for x in th]; [x.join() for x in th]
        if sorted(out.values()) == ["granted", "queued"]: ok += 1
        else: detail.append(out)
        a.kill(); b.kill(); shutil.rmtree(d, ignore_errors=True)
    results["2"] = (ok == 20, f"{ok}/20 lần đúng 1 granted + 1 queued {detail[:2]}")

def t10():
    d = tmp(); a, b = MCP(d, "A"), MCP(d, "B")
    a.tool("register_agent", tool="Claude Code", project="shop"); b.tool("register_agent", tool="Codex CLI", project="api")
    s1 = a.tool("acquire_slot", kind="xcode_build")["slot"]["status"]
    s2 = b.tool("acquire_slot", kind="gradle")["slot"]["status"]
    a.kill()
    s3 = b.tool("acquire_slot", kind="gradle")["slot"]["status"]
    results["10"] = (s1 == "granted" and s2 == "queued" and s3 == "granted", f"A {s1}, B {s2}; kill MCP của A; B xin lại: {s3}")
    b.kill(); shutil.rmtree(d, ignore_errors=True)

def t11():
    d = tmp(); b = MCP(d, "B")
    b.tool("register_agent", tool="Codex CLI", project="api")
    # Plant a holder whose MCP pid is alive (this harness) but with another start time: a reused pid.
    st = json.load(open(os.path.join(d, "state.json")))
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    st["agents"].append({"id": "a900", "tool": "Ghost", "project": "x", "pid": os.getpid(), "registeredAt": now, "lastSeen": now,
                         "mcp": {"pid": os.getpid(), "seconds": 1000000000, "microseconds": 0}})
    st["slots"].append({"id": "s900", "agentID": "a900", "kind": "gradle", "acquiredAt": now,
                        "expiresAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 1500))})
    json.dump(st, open(os.path.join(d, "state.json"), "w"))
    s = b.tool("acquire_slot", kind="gradle")["slot"]["status"]
    results["11"] = (s == "granted", f"slot của tiến trình có pid đang sống ({os.getpid()}) nhưng giờ khởi động khác: B xin được ngay ({s})")
    b.kill(); shutil.rmtree(d, ignore_errors=True)

def t12():
    d = tmp(); fake_dir = None
    fake = os.environ["FAKE_JOB"]   # tiny C program named xcodebuild that only sleeps
    a, b = MCP(d, "A"), MCP(d, "B")
    a.tool("register_agent", tool="Claude Code", project="shop"); b.tool("register_agent", tool="Codex CLI", project="api")
    r = a.tool("acquire_slot", kind="xcode_build", ttl_s=60)
    sid = r["slot"]["slot_id"]
    job = subprocess.Popen([fake, "300"])  # child of the harness = the session of both MCP processes
    b.tool("acquire_slot", kind="gradle")
    time.sleep(65)
    sl = b.tool("slots")
    mine = [s for s in sl.get("slots", []) if s.get("slot_id") == sid]
    q = b.tool("acquire_slot", kind="gradle")["slot"]["status"]
    cs = b.tool("can_start", kind="gradle")
    alive = job.poll() is None
    ok12 = bool(mine) and mine[0].get("lease") == "expired" and mine[0].get("task") == "running" and q == "queued" and alive
    results["12"] = (ok12, f"sau 65 s: lease={mine[0].get('lease') if mine else 'mất'}, task={mine[0].get('task') if mine else None}, busy_with={mine[0].get('busy_with') if mine else None}; B: {q}, can_start {cs.get('decision')}; việc nặng giả vẫn chạy: {alive}")
    job.terminate(); job.wait()   # our own fake job
    q2 = b.tool("acquire_slot", kind="gradle")["slot"]["status"]
    results["13"] = (q2 == "granted", f"việc nặng giả kết thúc: B được cấp ({q2})")
    a.kill(); b.kill(); shutil.rmtree(d, ignore_errors=True); None

def t17():
    d = tmp(); a, b = MCP(d, "A"), MCP(d, "B")
    st = a.tool("machine_status")
    a.tool("register_agent", tool="Claude Code", project="shop"); b.tool("register_agent", tool="Codex CLI", project="api")
    s1 = a.tool("acquire_slot", kind="gradle")["slot"]["status"]; s2 = b.tool("acquire_slot", kind="gradle")["slot"]["status"]
    ok = st.get("source") == "direct" and st.get("window_s") == 1 and s1 == "granted" and s2 == "queued"
    results["17"] = (ok, f"không có status.json: source={st.get('source')}, window_s={st.get('window_s')}, swap={st.get('swap_mb_per_min')}; phối hợp: {s1}/{s2}")
    a.kill(); b.kill(); shutil.rmtree(d, ignore_errors=True)

def t9():
    d = tmp(); a, b = MCP(d, "A"), MCP(d, "B")
    a.tool("register_agent", tool="Claude Code", project="shop"); b.tool("register_agent", tool="Codex CLI", project="api")
    sid = a.tool("acquire_slot", kind="gradle", ttl_s=1800)["slot"]["slot_id"]
    silent = int(os.environ.get("SILENT_S", "720"))
    time.sleep(silent)             # model A says nothing; its MCP process lives and heartbeats
    q = b.tool("acquire_slot", kind="gradle")["slot"]   # B's call runs expiry
    m = a.tool("my_slots")
    ok = q["status"] == "queued" and any(s.get("slot_id") == sid for s in m.get("slots", []))
    results["9"] = (ok, f"A im lặng {silent} s: A vẫn giữ {sid} ({[s.get('status') for s in m.get('slots', [])]}), B: {q['status']}")
    a.kill(); b.kill(); shutil.rmtree(d, ignore_errors=True)

for k in which:
    try: {"2": t2, "9": t9, "10": t10, "11": t11, "12": t12, "17": t17}[k]()
    except Exception as e: results[k] = (False, f"lỗi: {e}")
for k, (ok, why) in sorted(results.items(), key=lambda x: int(x[0])):
    print(f"{k}\t{'ĐẠT' if ok else 'TRƯỢT'}\t{why}")
