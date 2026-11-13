import json, os, subprocess, sys, tempfile, shutil
# Code Assembly banks [Sir R2; C++ since 2026-11-14]: per page, 8 variants. Each
# page teaches one beginner C++ lesson, in course order:
#   1 Scorch and Burn  Intro         first program: #include, main, return 0
#   2 Cultivate        Get Started   program layout; execution starts in main
#   3 Ring of Fire     Syntax        statements end with ;  { } blocks, namespace
#   4 Quick Step       Output        cout <<, chaining, endl and "\n"
#   5 Sage Arts        Comments      // line and /* block */ comments
#   6 Dragon's Breath  Variables     type name = value;  const
#   7 Firefly          User Input    cin >> into a declared variable
#   8 Explosion        Data Types    int, float, double, bool, char, string, auto
# A page's code uses only what its lesson and the earlier ones teach. All text
# is original. Each variant: lines in the correct order; "swap": groups of line
# indices that may come in any order among themselves. Variant 0 is shown on
# the unlocked page. Every variant is compiled with `g++ -fsyntax-only`.
#   python tools/make_code_assembly_bank.py data/puzzles/code_assembly.json
V = lambda *lines, swap=None: {"lines": list(lines), "swap": swap or []}
INC = "#include <iostream>"
USE = "using namespace std;"
MAIN = "int main() {"
RET = "  return 0;"
END = "}"
STR = "#include <string>"
def prog(*body, swap=None, use=True, head=None):
    top = [INC] + ([USE] if use else []) if head is None else list(head)
    return V(*top, MAIN, *body, RET, END, swap=swap)

BANK = {
 "scorch_and_burn": {"topic": "C++ Intro: your first program (#include, main, return 0)", "variants": [
  prog('  cout << "Scorch and Burn: the fireball flies!";'),
  prog('  cout << "A spark leaves your hand.";'),
  prog('  cout << "Flames answer the call.";'),
  prog('  cout << "The first page of the grimoire is open.";'),
  prog('  cout << "Burn marks the ground where it lands.";'),
  prog('  cout << "Fireball ready.";'),
  prog('  cout << "Heat gathers in your palm.";'),
  prog('  cout << "The scorch spreads three and a half metres.";'),
 ]},
 "cultivate": {"topic": "C++ Get Started: program layout; execution starts in main()", "variants": [
  prog('  cout << "Cultivate: focus gathers.";', '  cout << "Power, mastery and speed rise.";'),
  prog('  cout << "Breathe in.";', '  cout << "Breathe out.";'),
  prog('  cout << "The program starts here, inside main.";', '  cout << "Then it ends.";'),
  prog('  cout << "First line of the ritual.";', '  cout << "Second line of the ritual.";', '  cout << "Third line of the ritual.";'),
  prog('  cout << "Your magic grows stronger.";'),
  prog('  cout << "Ten seconds of focus.";', '  cout << "Focus fades.";'),
  prog('  cout << "Attack speed rises.";'),
  prog('  cout << "The aura glows in your hands.";', '  cout << "The aura dims.";'),
 ]},
 "ring_of_fire": {"topic": "C++ Syntax: statements end with ;, code lives in { } blocks, using namespace std", "variants": [
  prog('  cout << "Ring of Fire: six orbs circle you.";', '  cout << "They burn whatever they touch.";'),
  prog('  std::cout << "No using line: std:: names the library.";', use=False),
  prog('  {', '    cout << "An inner block.";', '  }'),
  prog('  cout << "One statement, one semicolon.";', '  cout << "Another statement, another semicolon.";'),
  prog('  std::cout << "Orbit begins.";', '  std::cout << "Orbit ends.";', use=False),
  prog('  {', '    cout << "First orb.";', '  }', '  {', '    cout << "Second orb.";', '  }'),
  prog('  cout << "Blocks open with { and close with }.";'),
  prog('  cout << "The ring follows you.";', '  {', '    cout << "It slows the burning.";', '  }'),
 ]},
 "quick_step": {"topic": "C++ Output: cout <<, chained output, endl and \\n", "variants": [
  prog('  cout << "Quick Step!" << endl;', '  cout << "Five metres in a blink." << endl;'),
  prog('  cout << "Left, right, ";', '  cout << "forward.\\n";'),
  prog('  cout << "Blink " << "and " << "gone." << endl;'),
  prog('  cout << "Line one" << endl;', '  cout << "Line two" << endl;', '  cout << "Line three" << endl;'),
  prog('  cout << "Step\\n";', '  cout << "Step again\\n";'),
  prog('  cout << "Cooldown: " << "ten seconds" << endl;'),
  prog('  cout << "No key held: " << endl << "step forward." << endl;'),
  prog('  cout << "Diagonal steps go the same distance.\\n";', '  cout << "Ready." << endl;'),
 ]},
 "sage_arts": {"topic": "C++ Comments: // single-line and /* multi-line */ notes the compiler skips", "variants": [
  prog('  // Out of combat: restore a little HP and MP.', '  cout << "Sage Arts: you rest." << endl;'),
  prog('  /* Sage Arts waits three seconds', '     after the last hit. */', '  cout << "Resting." << endl;'),
  prog('  cout << "HP returns." << endl; // three percent a second'),
  prog('  // cout << "This line never runs.";', '  cout << "Only this line runs." << endl;'),
  prog('  /* A block comment can span */', '  /* or close on the same line. */', '  cout << "Calm." << endl;'),
  prog('  cout << "MP returns." << endl; // five percent a second', '  // At full HP and MP, the passive rests.'),
  prog('  // Grace: any hit resets the wait.', '  cout << "Waiting..." << endl;', '  cout << "Restoring." << endl;'),
  prog('  /* Notes for the reader,', '     ignored by the compiler. */', '  cout << "The sage is quiet." << endl;'),
 ]},
 "dragons_breath": {"topic": "C++ Variables: type name = value; and const for values that never change", "variants": [
  prog('  int ticks = 10;', '  double power = 0.8;', '  cout << "Breath ticks: " << ticks << endl;', '  cout << "Power per tick: " << power << endl;', swap=[[3, 4]]),
  prog('  const int SECONDS = 5;', '  cout << "The breath lasts " << SECONDS << " seconds." << endl;'),
  prog('  string name = "Dragon\'s Breath";', '  cout << name << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
  prog('  int length = 20;', '  int width = 5;', '  cout << length << " m long, " << width << " m wide" << endl;', swap=[[3, 4]]),
  prog('  int mp = 50;', '  mp = mp - 50;', '  cout << "MP left: " << mp << endl;'),
  prog('  double tick = 0.5;', '  int count = 10;', '  cout << tick * count << " seconds of fire" << endl;', swap=[[3, 4]]),
  prog('  const double BURN = 5.0;', '  cout << "Burn: " << BURN << " s" << endl;'),
  prog('  int hits = 0;', '  hits = hits + 1;', '  hits = hits + 1;', '  cout << "Hits: " << hits << endl;'),
 ]},
 "firefly": {"topic": "C++ User Input: cin >> reads a value into a declared variable", "variants": [
  prog('  int targets;', '  cout << "How many targets? ";', '  cin >> targets;', '  cout << 30 / targets << " missiles each" << endl;'),
  prog('  int missiles;', '  cout << "Missiles: ";', '  cin >> missiles;', '  cout << "Launching " << missiles << endl;'),
  prog('  string target;', '  cout << "Lock on to: ";', '  cin >> target;', '  cout << "Locked: " << target << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
  prog('  double range;', '  cout << "Range in metres: ";', '  cin >> range;', '  cout << "Range set to " << range << endl;'),
  prog('  int a;', '  int b;', '  cout << "Two numbers: ";', '  cin >> a >> b;', '  cout << a + b << endl;', swap=[[3, 4]]),
  prog('  int mp;', '  cout << "Your MP: ";', '  cin >> mp;', '  cout << "After Firefly: " << mp - 70 << endl;'),
  prog('  int seconds;', '  cin >> seconds;', '  cout << "Cooldown " << seconds << " s" << endl;'),
  prog('  string name;', '  cout << "Name your spell: ";', '  cin >> name;', '  cout << name << " is ready." << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
 ]},
 "explosion": {"topic": "C++ Data Types: int, float, double, bool, char, string and auto", "variants": [
  prog('  int damage = 1000;', '  double radius = 25.0;', '  bool charged = true;', '  cout << damage << " " << radius << " " << charged << endl;', swap=[[3, 4, 5]]),
  prog('  char grade = \'E\';', '  cout << "Rank " << grade << endl;'),
  prog('  float seconds = 20.0f;', '  cout << "Charge: " << seconds << " s" << endl;'),
  prog('  string spell = "Explosion";', '  bool ready = false;', '  cout << spell << " ready: " << ready << endl;', head=[INC, STR, USE], swap=[[0, 1], [4, 5]]),
  prog('  auto metres = 80;', '  cout << "Reach: " << metres << " m" << endl;'),
  prog('  int whole = 7;', '  double precise = 7.25;', '  cout << whole << " and " << precise << endl;', swap=[[3, 4]]),
  prog('  bool broken = false;', '  char mark = \'!\';', '  cout << broken << mark << endl;', swap=[[3, 4]]),
  prog('  auto power = 10.0;', '  auto count = 1;', '  cout << power * count << endl;', swap=[[3, 4]]),
 ]},
}

def gpp():
    for name in ("g++", "g++.exe"):
        p = shutil.which(name)
        if p: return p
    return None

bad = 0
compiler = gpp()
if compiler is None:
    print("g++ not found: cannot check the bank"); sys.exit(2)
for pid, b in BANK.items():
    assert len(b["variants"]) >= 8, pid
    for i, v in enumerate(b["variants"]):
        for g in v["swap"]:
            assert all(0 <= k < len(v["lines"]) for k in g), (pid, i)
        with tempfile.NamedTemporaryFile("w", suffix=".cpp", delete=False, encoding="utf-8") as f:
            f.write("\n".join(v["lines"]) + "\n")
            path = f.name
        r = subprocess.run([compiler, "-std=c++17", "-fsyntax-only", "-Wall", "-Werror", path], capture_output=True, text=True)
        os.unlink(path)
        if r.returncode != 0:
            bad += 1; print("G++", pid, i, r.stderr.strip()[:300])
if bad:
    print("compile errors:", bad); sys.exit(1)
out = sys.argv[1]
json.dump(BANK, open(out, "w", encoding="utf-8", newline="\n"), indent=1, ensure_ascii=False)
print("ok", {k: len(v["variants"]) for k, v in BANK.items()}, "compiled with", compiler)
