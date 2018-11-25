import os, osproc, parseutils, httpclient, json
import strutils except toLower
import unicode except strip

type
  IssueStatus = enum
    Fixed, Referenced
  Issue = object
    status: IssueStatus
    number: int

proc getCommitList(ver: string): seq[tuple[hash, desc: string]] =
  result = @[]
  let (output, exitCode) = execCmdEx("git log --oneline --reverse " & ver &
      "..HEAD")
  for line in splitLines(output):
    result.add((line.substr(0, 6), line.substr(7)))

proc parseCommit(commit: string, issues: var seq[Issue], next: int = 0): bool =
  var startAgainOn = 0
  var issue: Issue

  var i = next
  i += skipUntil(commit, '#', i)
  if commit[i] != '#': return false
  let processed = parseInt(commit, issue.number, i+1)
  if processed == 0: return false

  startAgainOn = i + processed + 1

  if commit[i-1] != ' ': return false
  i.dec # Skip space
  var word = ""
  while i > 0:
    i.dec
    if commit[i] in {' ', '(', '[', '.', '\''}: break
    if commit[i] in {':'}: continue
    word.add commit[i]
  word = word.reversed()

  case word.toLower()
  of "fixes", "fix", "fixed", "closes", "implement", "bug", "sigsegv",
     "conversion", "resolve", "fixup", "rfc", "close":
    result = true
    issue.status = Fixed
  of "request", "refs":
    result = false
  else:
    echo "```\"", commit, "\": unsure whether to include this, should I? [y/n]"
    let answer = stdin.readLine()
    echo "```"
    case answer.strip()
    of "y", "yes":
      result = true
      issue.status = Fixed
    of "n", "no":
      result = false
    else: doAssert false

  issues.add issue
  result = result or parseCommit(commit, issues, startAgainOn)

proc getIssueTitle(repo: string, issue: int, token: string): string =
  let url = "https://api.github.com/repos/$1/issues/$2" % [repo, $issue]
  let client = newHttpClient()
  if token.len > 0:
    client.headers = newHttpHeaders({
      "Authorization": "token $1" % token
    })
  let content = client.getContent(url)
  let parsed = parseJson(content)
  return parsed["title"].str

when isMainModule:
  let repo = "nim-lang/Nim"

  let token = if paramCount() >= 1: paramStr(1) else: ""

  if token.len == 0:
    echo("WARNING: You have not specified a GitHub token as a command line " &
         "argument. You will run into the rate limit quickly without it.")
    sleep(2000)
  else:
    echo("Thank you for supplying your GitHub token")

  # Are we in a git dir?
  if not existsDir(getCurrentDir() / ".git"):
    quit("Current dir is not a Git repo: no .git directory found.")

  # Issue number to start requests to GH after.
  # Until this issue number is found, the issues will not be echoed.
  # Use `-1` to start immediately.
  let requestAfter = -1
  # Get a list of commits.
  var started = requestAfter == -1
  let commits = getCommitList("v0.19.0")
  for c in commits:
    var issues: seq[Issue] = @[]
    if parseCommit(c.desc, issues):
      for i in issues:
        if started:
          let title = getIssueTitle(repo, i.number, token)
          let url = "https://github.com/$1/issues/$2" % [repo, $i.number]
          let str = "- Fixed \"$1\"\n  ([#$2]($3))" % [title, $i.number, url]
          echo(str)
        if i.number == requestAfter: started = true
