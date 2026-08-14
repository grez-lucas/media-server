#!/usr/bin/env python3
"""Apply seed/conventions.json to a running stack, or refuse and explain why.

Invoked through scripts/seed.sh, which asserts the interpreter first.

WHAT THIS IS
    Issue #7 decided that Tier 1 conventions - root folders, naming templates,
    library definitions - travel with the repo and are applied by an idempotent
    script driving the service APIs. Not committed config files: Radarr's and
    Sonarr's settings live inside radarr.db / sonarr.db, so there is no *arr file
    to commit and "commit the config" would reach Tier 1 for one service of three.

CONVERGE OR REFUSE
    docs/library-layout.md calls a change to these values "a migration, not an
    edit", so the seed must never quietly rewrite them.

        blank service       apply the data file
        configured service  compare, report every difference, write NOTHING
        --force             converge regardless

    "Blank" is not a guess about the host. It is observed per service: a Radarr
    or Sonarr with no root folders, or a Jellyfin whose startup wizard has not
    run, has nothing a human could have deliberated. Anything else is configured.

    Planning happens for every service BEFORE anything is written, and a single
    refusal stops the whole run. A half-seeded host is harder to reason about
    than an untouched one.

    That one code path makes the seeder its own drift checker, which is what CI
    calls to assert a running stack still matches the file.

SECRETS ARE INJECTED, NEVER DISCOVERED
    Every credential comes from .env. Nothing gitignored is ever read. Radarr and
    Sonarr take their API key from the environment; Jellyfin accepts no API call
    until its wizard has run, and that step requires creating an admin with a
    password, so a blank host must supply one. A host whose wizard has already
    run can supply a JELLYFIN_API_KEY instead and keep its password to itself.

STANDARD LIBRARY ONLY
    No third-party packages. Comparing declared values against live ones is the
    core of the script, json does it natively, and hand-rolling that comparison
    in grep and sed is how false greens get built.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONVENTIONS = os.path.join(REPO_ROOT, "seed", "conventions.json")

# Jellyfin wants this on every authenticated call.
JF_AUTH = (
    'MediaBrowser Client="media-server-seed", Device="seed", '
    'DeviceId="media-server-seed", Version="1.0.0"'
)

_QUIET = False


# --- output -----------------------------------------------------------------

def _c(code, text):
    return text if os.environ.get("NO_COLOR") else "\033[%sm%s\033[0m" % (code, text)


def step(msg):
    if not _QUIET:
        print("\n%s" % _c("1", "==> " + msg))


def ok(msg):
    if not _QUIET:
        print("  %s %s" % (_c("32", "OK  "), msg))


def note(msg):
    if not _QUIET:
        print("  %s %s" % (_c("33", "NOTE"), msg))


def wrote(msg):
    print("  %s %s" % (_c("36", "SET "), msg))


def die(msg, code=2):
    print("\n%s %s" % (_c("31", "FAIL"), msg), file=sys.stderr)
    raise SystemExit(code)


# --- environment ------------------------------------------------------------

# Every variable the seed reads. Listed rather than inferred so that a real
# environment variable can win over the file without dragging in every unrelated
# uppercase name the shell happens to export.
ENV_KEYS = (
    "JELLYFIN_PORT", "RADARR_PORT", "SONARR_PORT",
    "RADARR_API_KEY", "SONARR_API_KEY",
    "JELLYFIN_API_KEY", "JELLYFIN_ADMIN_USER", "JELLYFIN_ADMIN_PASSWORD",
)


def load_env(path):
    """Parse the KEY=VALUE subset of .env that compose supports.

    A real environment variable always wins, so CI can inject without a file.
    """
    values = {}
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                val = val.strip()
                if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                    val = val[1:-1]
                values[key.strip()] = val
    values.update({k: os.environ[k] for k in ENV_KEYS if os.environ.get(k)})
    return values


# --- http -------------------------------------------------------------------

class Http(Exception):
    def __init__(self, status, body, url):
        super().__init__("HTTP %s from %s: %s" % (status, url, body[:300]))
        self.status = status
        self.body = body


def request(url, method="GET", headers=None, payload=None, timeout=30):
    data = None
    headers = dict(headers or {})
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        raise Http(exc.code, exc.read().decode("utf-8", "replace"), url)
    except urllib.error.URLError as exc:
        raise Http(0, str(exc.reason), url)
    if not body.strip():
        return None
    try:
        return json.loads(body)
    except ValueError:
        return body


def wait_ready(name, url, probe, attempts=90, delay=2):
    """Readiness, not liveness.

    Issue #6 caught this exact bug once: Jellyfin serves HTTP 200 on / while
    every API call still answers 503 "Jellyfin Server is loading", so polling /
    passes too early and the next step fails for a reason that looks unrelated.
    Probe something that only answers once the application is genuinely up.
    """
    last = ""
    for i in range(1, attempts + 1):
        try:
            body = request(url, timeout=5)
            if probe(body):
                ok("%s ready after ~%ds" % (name, i * delay))
                return
            last = repr(body)[:120]
        except Http as exc:
            last = str(exc)[:120]
        except Exception as exc:  # noqa: BLE001 - report whatever went wrong
            last = str(exc)[:120]
        time.sleep(delay)
    die("%s never became ready at %s (last: %s)" % (name, url, last))


# --- the data file ----------------------------------------------------------

def declared(mapping):
    """Strip commentary. Keys beginning with _ are prose for humans."""
    return {k: v for k, v in mapping.items() if not k.startswith("_")}


class Change:
    """One difference between the data file and a running service.

    `group` is the unit of WRITING, which is coarser than the unit of REPORTING.
    Radarr's naming template is one PUT carrying several keys, so three drifted
    keys are three lines a human reads but one call the seed makes. Changes
    sharing a group apply exactly once.
    """

    def __init__(self, service, what, desired, actual, apply_fn, group=None):
        self.service = service
        self.what = what
        self.desired = desired
        self.actual = actual
        self.apply_fn = apply_fn
        self.group = group or "%s:%s" % (service, what)

    def line(self):
        if self.actual is _ABSENT:
            return "%-8s %-46s missing, would create -> %s" % (
                self.service, self.what, _short(self.desired))
        return "%-8s %-46s is %s, data file says %s" % (
            self.service, self.what, _short(self.actual), _short(self.desired))


class _Absent:
    def __repr__(self):
        return "<absent>"


_ABSENT = _Absent()


def _short(value):
    text = value if isinstance(value, str) else json.dumps(value)
    return text if len(text) <= 60 else text[:57] + "..."


# --- Jellyfin ---------------------------------------------------------------

class Jellyfin:
    name = "jellyfin"

    def __init__(self, base, env):
        self.base = base
        self.env = env
        self.token = None
        self.api_key = env.get("JELLYFIN_API_KEY") or ""
        self.blank = False
        self._pending_wizard = False

    def headers(self):
        head = {"X-Emby-Authorization": JF_AUTH}
        if self.api_key:
            head["X-Emby-Token"] = self.api_key
        elif self.token:
            head["X-Emby-Token"] = self.token
        return head

    def call(self, path, method="GET", payload=None):
        return request(self.base + path, method, self.headers(), payload)

    def wait(self):
        wait_ready("jellyfin", self.base + "/System/Info/Public",
                   lambda b: isinstance(b, dict) and "Version" in b)

    def authenticate(self):
        user = self.env.get("JELLYFIN_ADMIN_USER")
        pw = self.env.get("JELLYFIN_ADMIN_PASSWORD")
        if self.api_key:
            ok("authenticating with JELLYFIN_API_KEY")
            return
        if not user or not pw:
            die("jellyfin needs credentials from .env: set JELLYFIN_API_KEY, or "
                "JELLYFIN_ADMIN_USER and JELLYFIN_ADMIN_PASSWORD.\n"
                "     They are injected, never discovered - see .env.example.")
        try:
            body = self.call("/Users/AuthenticateByName", "POST",
                             {"Username": user, "Pw": pw})
        except Http as exc:
            die("could not authenticate to jellyfin as %r: %s\n"
                "     On a host whose wizard already ran, these must be a real "
                "account's credentials." % (user, exc))
        self.token = body.get("AccessToken")
        if not self.token:
            die("jellyfin authentication returned no access token")
        ok("authenticated as %s" % user)

    def plan(self, spec):
        info = self.call("/System/Info/Public")
        if not info.get("StartupWizardCompleted"):
            # Nothing to compare: a host that has not run the wizard cannot hold
            # a deliberated setting. Definitionally blank.
            self.blank = True
            self._pending_wizard = True
            changes = [Change("jellyfin", "startup wizard", "completed", _ABSENT,
                              self._run_wizard)]
            for lib in spec["libraries"]:
                changes.append(Change("jellyfin", "library %r" % lib["name"],
                                      lib["path"], _ABSENT,
                                      lambda l=lib: self._create_library(l)))
            return changes

        self.authenticate()
        existing = {f["Name"]: f for f in self.call("/Library/VirtualFolders")}
        self.blank = not existing

        changes = []
        for lib in spec["libraries"]:
            live = existing.get(lib["name"])
            if live is None:
                changes.append(Change("jellyfin", "library %r" % lib["name"],
                                      lib["path"], _ABSENT,
                                      lambda l=lib: self._create_library(l)))
                continue
            if lib["path"] not in (live.get("Locations") or []):
                changes.append(Change(
                    "jellyfin", "library %r path" % lib["name"], lib["path"],
                    live.get("Locations") or [],
                    lambda l=lib: self._add_path(l)))
            want = declared(lib.get("options", {}))
            live_opts = live.get("LibraryOptions") or {}
            drift = {k: v for k, v in want.items() if live_opts.get(k) != v}
            for key, value in drift.items():
                changes.append(Change(
                    "jellyfin", "library %r option %s" % (lib["name"], key),
                    value, live_opts.get(key, _ABSENT),
                    lambda l=lib, lv=live, d=drift: self._set_options(l, lv, d),
                    group="jellyfin:options:%s" % lib["name"]))

        declared_names = {l["name"] for l in spec["libraries"]}
        for extra in sorted(set(existing) - declared_names):
            note("jellyfin has a library %r that the data file does not declare. "
                 "The seed declares what must exist, not what must not, so this "
                 "is left alone." % extra)
        return changes

    def _run_wizard(self):
        user = self.env.get("JELLYFIN_ADMIN_USER")
        pw = self.env.get("JELLYFIN_ADMIN_PASSWORD")
        if not user or not pw:
            die("jellyfin's startup wizard has not run, and it cannot be completed "
                "without creating an admin WITH a password.\n"
                "     Set JELLYFIN_ADMIN_USER and JELLYFIN_ADMIN_PASSWORD in .env. "
                "A JELLYFIN_API_KEY is not enough here - there is no account to "
                "issue one yet.")
        # No auth header on the /Startup/* calls. They sit behind Jellyfin's
        # FirstTimeSetupOrElevated policy; sending one makes Jellyfin treat the
        # call as authenticated, the policy then fails, and it answers 404.
        request(self.base + "/Startup/Configuration", "POST", payload={
            "UICulture": "en-US", "MetadataCountryCode": "US",
            "PreferredMetadataLanguage": "en"})
        # GET first, and not for symmetry: it materialises the default startup
        # user that the POST then renames. Without it the POST has nothing to
        # update and Jellyfin answers 404.
        request(self.base + "/Startup/User")
        request(self.base + "/Startup/User", "POST",
                payload={"Name": user, "Password": pw})
        request(self.base + "/Startup/Complete", "POST")
        wrote("jellyfin startup wizard completed, admin %r created" % user)
        self._pending_wizard = False
        self.api_key = ""  # a key cannot have existed before the wizard ran
        self.authenticate()

    def _create_library(self, lib):
        if self._pending_wizard:
            self._run_wizard()
        query = urllib.parse.urlencode({
            "name": lib["name"],
            "collectionType": lib["collectionType"],
            "paths": lib["path"],
            "refreshLibrary": "true",
        })
        # A full LibraryOptions payload is deliberately NOT sent. An API-created
        # library writes an empty <TypeOptions /> where a UI-created one carries
        # a populated block, and #7 left open whether empty meant "fetch
        # nothing". Measured on 10.11.11, two libraries, one fixture: identical
        # ProviderIds, rating, genres, images and overview. Empty falls back to
        # defaults at runtime, so only the declared options are sent.
        self.call("/Library/VirtualFolders?" + query, "POST",
                  {"LibraryOptions": declared(lib.get("options", {}))})
        wrote("jellyfin library %r created at %s" % (lib["name"], lib["path"]))

    def _add_path(self, lib):
        self.call("/Library/VirtualFolders/Paths?refreshLibrary=true", "POST",
                  {"Name": lib["name"], "Path": lib["path"]})
        wrote("jellyfin library %r now includes %s" % (lib["name"], lib["path"]))

    def _set_options(self, lib, live, drift):
        merged = dict(live.get("LibraryOptions") or {})
        merged.update(drift)
        self.call("/Library/VirtualFolders/LibraryOptions", "POST",
                  {"Id": live["ItemId"], "LibraryOptions": merged})
        wrote("jellyfin library %r options: %s"
              % (lib["name"], ", ".join("%s=%s" % kv for kv in drift.items())))


# --- Radarr and Sonarr ------------------------------------------------------

class Arr:
    """Radarr and Sonarr speak the same v3 API for everything the seed touches."""

    def __init__(self, name, base, api_key):
        self.name = name
        self.base = base
        self.api_key = api_key
        self.blank = False

    def call(self, path, method="GET", payload=None):
        return request(self.base + "/api/v3" + path, method,
                       {"X-Api-Key": self.api_key}, payload)

    def wait(self):
        wait_ready(self.name, self.base + "/ping",
                   lambda b: isinstance(b, dict) and b.get("status") == "OK")

    def plan(self, spec):
        if not self.api_key:
            die("%s needs %s_API_KEY in .env. It is injected, never discovered - "
                "see .env.example." % (self.name, self.name.upper()))
        try:
            roots = self.call("/rootfolder")
        except Http as exc:
            if exc.status == 401:
                die("%s rejected %s_API_KEY (HTTP 401). The key in .env must be "
                    "the one compose injected as %s__AUTH__APIKEY; if you changed "
                    "it, recreate the container so it takes effect."
                    % (self.name, self.name.upper(), self.name.upper()))
            raise
        live_paths = [r["path"] for r in roots]
        self.blank = not roots

        changes = []
        for path in spec["rootFolders"]:
            if path not in live_paths:
                changes.append(Change(self.name, "root folder", path, _ABSENT,
                                      lambda p=path: self._add_root(p)))
        for extra in sorted(set(live_paths) - set(spec["rootFolders"])):
            note("%s has a root folder %s that the data file does not declare. "
                 "Left alone." % (self.name, extra))

        for section, endpoint in (("naming", "/config/naming"),
                                  ("mediaManagement", "/config/mediamanagement")):
            want = declared(spec.get(section, {}))
            if not want:
                continue
            live = self.call(endpoint)
            drift = {k: v for k, v in want.items() if live.get(k) != v}
            for key, value in drift.items():
                changes.append(Change(
                    self.name, "%s.%s" % (section, key), value,
                    live.get(key, _ABSENT),
                    lambda e=endpoint, lv=live, d=drift: self._put(e, lv, d),
                    group="%s:%s" % (self.name, section)))
        return changes

    def _add_root(self, path):
        self.call("/rootfolder", "POST", {"path": path})
        wrote("%s root folder %s added" % (self.name, path))

    def _put(self, endpoint, live, drift):
        merged = dict(live)
        merged.update(drift)
        self.call("%s/%s" % (endpoint, live["id"]), "PUT", merged)
        wrote("%s %s: %s" % (self.name, endpoint.rsplit("/", 1)[-1],
                             ", ".join("%s=%s" % kv for kv in drift.items())))


# --- main -------------------------------------------------------------------

def main(argv=None):
    global _QUIET

    parser = argparse.ArgumentParser(
        prog="scripts/seed.sh",
        description="Apply seed/conventions.json to a running stack.")
    parser.add_argument("--force", action="store_true",
                        help="converge a configured host instead of refusing")
    parser.add_argument("--env-file", default=os.path.join(REPO_ROOT, ".env"),
                        help="where the injected secrets live (default: ./.env)")
    parser.add_argument("--host", default=os.environ.get("SEED_HOST", "127.0.0.1"),
                        help="host the services are published on")
    parser.add_argument("--quiet", action="store_true",
                        help="print only differences and writes")
    args = parser.parse_args(argv)
    _QUIET = args.quiet

    env = load_env(args.env_file)

    with open(CONVENTIONS, encoding="utf-8") as fh:
        spec = json.load(fh)

    def port(key, default):
        return env.get(key) or str(default)

    services = [
        Jellyfin("http://%s:%s" % (args.host, port("JELLYFIN_PORT", 8096)), env),
        Arr("radarr", "http://%s:%s" % (args.host, port("RADARR_PORT", 7878)),
            env.get("RADARR_API_KEY", "")),
        Arr("sonarr", "http://%s:%s" % (args.host, port("SONARR_PORT", 8989)),
            env.get("SONARR_API_KEY", "")),
    ]

    step("Waiting for the stack")
    for svc in services:
        svc.wait()

    step("Comparing the running stack against seed/conventions.json")
    changes, refusals = [], []
    for svc in services:
        found = svc.plan(spec[svc.name])
        changes.extend(found)
        if found and not svc.blank:
            refusals.extend(found)
        elif found:
            ok("%s is blank - %d convention(s) to apply" % (svc.name, len(found)))
        else:
            ok("%s already matches the data file" % svc.name)

    if not changes:
        step("Nothing to do")
        print("\n%s" % _c("32", "ALREADY SEEDED"))
        return 0

    if refusals and not args.force:
        step("This host disagrees with the data file")
        for change in refusals:
            print("  %s %s" % (_c("31", "DIFF"), change.line()))
        print(
            "\n%s\n"
            "  These services are already configured, and docs/library-layout.md\n"
            "  calls a change to these values a migration rather than an edit -\n"
            "  so nothing was written.\n\n"
            "  Converge deliberately:      scripts/seed.sh --force\n"
            "  Or, if the host is right:   change seed/conventions.json, and give\n"
            "                              the new value a reason in\n"
            "                              docs/library-layout.md.\n"
            % _c("31", "REFUSED - nothing written"))
        return 1

    step("Applying" + (" (--force)" if args.force else ""))
    applied = set()
    for change in changes:
        if change.group in applied:
            continue  # several keys in one section share a single write
        change.apply_fn()
        applied.add(change.group)

    print("\n%s" % _c("32", "SEEDED"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Http as exc:
        die(str(exc))
    except KeyboardInterrupt:
        die("interrupted", 130)
