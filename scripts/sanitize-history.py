"""One-time, explicitly authorized cleanup for this new diagnostic repository.

Replaces only main's ancestry, preserving its exact tree. Uses the repository's
short-lived workflow token and GitHub no-reply author metadata. This cannot
purge cached or already downloaded copies of old commits.
"""
import json
import os
from urllib.request import Request, urlopen

repository = os.environ["GITHUB_REPOSITORY"]
owner = os.environ["GITHUB_REPOSITORY_OWNER"]
owner_id = os.environ["GITHUB_REPOSITORY_OWNER_ID"]
expected = os.environ["GITHUB_SHA"]
token = os.environ["GH_TOKEN"]
if repository.split("/")[1] != "offline-teleprompter-lab":
    raise SystemExit("Unexpected repository; refusing to rewrite history")
if os.environ["GITHUB_ACTOR"] != owner:
    raise SystemExit("Only the repository owner may request this cleanup")


def api(method, path, data=None):
    request = Request("https://api.github.com/repos/" + repository + path,
        data=None if data is None else json.dumps(data).encode(), method=method,
        headers={"Authorization": "Bearer " + token,
                 "Accept": "application/vnd.github+json",
                 "Content-Type": "application/json",
                 "User-Agent": "teleprompter-author-cleanup"})
    with urlopen(request, timeout=30) as response:
        if response.status == 204:
            return {}
        return json.load(response)


if not api("GET", "")["private"]:
    raise SystemExit("Cleanup must run while the repository is private")
head = api("GET", "/git/ref/heads/main")
if head["object"]["sha"] != expected:
    raise SystemExit("Main changed; refusing to overwrite another revision")
old = api("GET", "/git/commits/" + expected)
identity = {"name": owner, "email": owner_id + "+" + owner + "@users.noreply.github.com"}
if not old["parents"] and old["author"]["email"] == identity["email"] and old["committer"]["email"] == identity["email"]:
    clean = old
else:
    clean = api("POST", "/git/commits", {"tree": old["tree"]["sha"], "parents": [],
        "message": "Offline Mandarin diagnostic prototype and unsigned test build",
        "author": identity, "committer": identity})
if clean["tree"]["sha"] != old["tree"]["sha"]:
    raise SystemExit("Tree mismatch; refusing to modify main")
if clean["sha"] != expected:
    api("PATCH", "/git/refs/heads/main", {"sha": clean["sha"], "force": True})
verified = api("GET", "/git/commits/" + api("GET", "/git/ref/heads/main")["object"]["sha"])
if verified["parents"] or verified["author"]["email"] != identity["email"]:
    raise SystemExit("Cleanup verification failed")
if verified["tree"]["sha"] != old["tree"]["sha"]:
    raise SystemExit("Code preservation verification failed")
print("CLEANUP_OK: current main has no-reply author metadata and no personal-email ancestry.")
print("CODE_PRESERVED: exact same Git tree before and after cleanup.")
print("CLEAN_HEAD:", verified["sha"])

# A workflow-run API response also embeds the original author email. Remove
# only completed records with that metadata, retaining code and the clean run.
# The unsigned package and required evidence were independently preserved.
removed = 0
for run in api("GET", "/actions/runs?per_page=100")["workflow_runs"]:
    source = run.get("head_commit") or {}
    emails = [source.get(role, {}).get("email", "") for role in ("author", "committer")]
    has_personal_email = any(email and not email.endswith("@users.noreply.github.com") for email in emails)
    if run["status"] == "completed" and has_personal_email:
        api("DELETE", "/actions/runs/" + str(run["id"]))
        removed += 1
print("OLD_EMAIL_WORKFLOW_RECORDS_REMOVED:", removed)
if clean["sha"] != expected:
    print("Run this manual cleanup once more from the clean main branch to remove this run's old-source metadata.")
