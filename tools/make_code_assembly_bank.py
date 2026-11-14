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
#   9 Flight of the Phoenix  Operators  + - * / %, ++, +=
#  10 Call of the Phoenix    Strings    string, + to join, .length()
#  11 Rise of the Phoenix    Math       <cmath>: max, min, sqrt, pow, round
#  12 Heads or Tails         Booleans   bool, true/false, comparisons == != < > <= >=
#  13 Where are my Coins?    If...Else  if, else if, else
#  14 Let it Ride            Switch     switch, case, break, default
#  15 All In                 While Loop while (condition) { }, do { } while
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
MATH = "#include <cmath>"
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
  prog('  int ticks = 20;', '  double power = 0.02;', '  cout << "Breath ticks: " << ticks << endl;', '  cout << "Power per tick: " << power << endl;', swap=[[3, 4]]),
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
 "flight_of_the_phoenix": {"topic": "C++ Operators: + - * / %, ++ and += to work out values", "variants": [
  prog('  int climb = 30;', '  int seconds = 5;', '  cout << "Climb speed: " << climb / seconds << " m/s" << endl;', '  cout << "Peak damage: " << 100 * 5 << "%" << endl;', swap=[[3, 4]]),
  prog('  int mp = 100;', '  mp -= 80;', '  cout << "MP left: " << mp << endl;'),
  prog('  int kills = 0;', '  kills++;', '  kills++;', '  cout << "Kills: " << kills << endl;'),
  prog('  int fireballs = 31;', '  cout << fireballs / 3 << " each, " << fireballs % 3 << " left over" << endl;'),
  prog('  double damage = 1.0;', '  damage *= 5;', '  cout << "Damage x" << damage << endl;'),
  prog('  int radius = 20;', '  int across = radius * 2;', '  cout << "Blast " << across << " m across" << endl;'),
  prog('  int height = 0;', '  height += 30;', '  height -= 30;', '  cout << "Back on the ground: " << height << endl;'),
  prog('  double t = 3.5;', '  double extra = (t - 2) / 3 * 4;', '  cout << "Bonus: " << extra << endl;'),
 ]},
 "call_of_the_phoenix": {"topic": "C++ Strings: string text, joining with +, and .length()", "variants": [
  prog('  string spell = "Call of the Phoenix";', '  cout << spell << " has " << spell.length() << " letters" << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
  prog('  string first = "Fire";', '  string second = "rain";', '  string both = first + " " + second;', '  cout << both << endl;', head=[INC, STR, USE], swap=[[0, 1], [4, 5]]),
  prog('  string area = "Area ";', '  cout << area + "1 locked" << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
  prog('  string word = "Phoenix";', '  cout << word.length() << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
  prog('  string name;', '  cout << "Name an area: ";', '  cin >> name;', '  cout << "Rain falls on " + name << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
  prog('  string call = "Call";', '  call += " of the Phoenix";', '  cout << call << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
  prog('  string rain = "30 fireballs";', '  string time = "5 seconds";', '  cout << rain + " in " + time << endl;', head=[INC, STR, USE], swap=[[0, 1], [4, 5]]),
  prog('  string empty = "";', '  cout << "Length: " << empty.length() << endl;', head=[INC, STR, USE], swap=[[0, 1]]),
 ]},
 "rise_of_the_phoenix": {"topic": "C++ Math: <cmath> functions max, min, sqrt, pow and round", "variants": [
  prog('  int kills = 12;', '  cout << "Rise " << min(kills, 20) << "/20" << endl;', head=[INC, MATH, USE], swap=[[0, 1]]),
  prog('  double hp = 0.0;', '  hp = max(hp, 100.0);', '  cout << "Reborn with " << hp << " HP" << endl;', head=[INC, MATH, USE], swap=[[0, 1]]),
  prog('  cout << sqrt(400) << " m knockback" << endl;', head=[INC, MATH, USE], swap=[[0, 1]]),
  prog('  cout << pow(2, 5) << endl;', head=[INC, MATH, USE], swap=[[0, 1]]),
  prog('  double heal = 2.4;', '  cout << round(heal) << "% healed" << endl;', head=[INC, MATH, USE], swap=[[0, 1]]),
  prog('  int a = 7;', '  int b = 3;', '  cout << max(a, b) << " beats " << min(a, b) << endl;', head=[INC, MATH, USE], swap=[[0, 1], [4, 5]]),
  prog('  double mp = 100.0;', '  mp = min(mp + 2.0, 100.0);', '  cout << mp << endl;', head=[INC, MATH, USE], swap=[[0, 1]]),
  prog('  double x = 3.0;', '  double y = 4.0;', '  cout << sqrt(pow(x, 2) + pow(y, 2)) << endl;', head=[INC, MATH, USE], swap=[[0, 1], [4, 5]]),
 ]},
 "heads_or_tails": {"topic": "C++ Booleans: bool, true and false, and comparisons that give a bool", "variants": [
  prog('  bool heads = true;', '  bool tails = false;', '  cout << "Heads: " << heads << ", Tails: " << tails << endl;', swap=[[3, 4]]),
  prog('  int flip = 1;', '  cout << (flip == 1) << endl;'),
  prog('  int range = 30;', '  int target = 25;', '  cout << "In range: " << (target <= range) << endl;', swap=[[3, 4]]),
  prog('  int bounces = 3;', '  cout << (bounces > 3) << endl;'),
  prog('  bool pocketChange = true;', '  cout << boolalpha << pocketChange << endl;'),
  prog('  int coin = 0;', '  bool isTails = coin != 1;', '  cout << "Tails? " << isTails << endl;'),
  prog('  int damage = 80;', '  int bonus = 110;', '  cout << (bonus >= damage) << endl;', swap=[[3, 4]]),
  prog('  bool hit = 15 < 20;', '  cout << boolalpha << "Hit: " << hit << endl;'),
 ]},
 "where_are_my_coins": {"topic": "C++ If...Else: if, else if and else choose which code runs", "variants": [
  prog('  int coins = 10;', '  if (coins == 10) {', '    cout << "Pockets full!" << endl;', '  }'),
  prog('  int coins = 4;', '  if (coins < 10) {', '    cout << "Keep collecting." << endl;', '  } else {', '    cout << "Ready to spend." << endl;', '  }'),
  prog('  bool buffed = true;', '  if (buffed) {', '    cout << "The coins are spent." << endl;', '  }'),
  prog('  int slow = 80;', '  if (slow > 50) {', '    cout << "Heavy pockets!" << endl;', '  } else if (slow > 0) {', '    cout << "Lighter now." << endl;', '  } else {', '    cout << "Free to run." << endl;', '  }'),
  prog('  int kills = 12;', '  int coins = kills;', '  if (coins > 10) {', '    coins = 10;', '  }', '  cout << coins << " coins" << endl;'),
  prog('  int distance = 25;', '  if (distance <= 30) {', '    cout << "Caught in the spill." << endl;', '  } else {', '    cout << "Too far away." << endl;', '  }'),
  prog('  bool slowed = false;', '  if (!slowed) {', '    cout << "Coins can be gained." << endl;', '  }'),
  prog('  int coins = 10;', '  bool buffed = true;', '  if (coins == 10 && buffed) {', '    cout << "Spend all ten!" << endl;', '  }', swap=[[3, 4]]),
 ]},
 "let_it_ride": {"topic": "C++ Switch: switch picks one case; break stops it; default catches the rest", "variants": [
  prog('  int roll = 6;', '  switch (roll) {', '    case 6:', '      cout << "JACKPOT!" << endl;', '      break;', '    default:', '      cout << "Roll again." << endl;', '  }'),
  prog('  int roll = 2;', '  switch (roll) {', '    case 1:', '    case 2:', '    case 3:', '      cout << "Buffs lost." << endl;', '      break;', '  }', swap=[[5, 6, 7]]),
  prog('  int roll = 4;', '  switch (roll) {', '    case 4:', '    case 5:', '      cout << "Gambler\'s High" << endl;', '      break;', '    case 6:', '      cout << "Jackpot" << endl;', '      break;', '  }', swap=[[5, 6]]),
  prog('  int face = 3;', '  switch (face) {', '    case 3:', '      cout << "Three pips." << endl;', '      break;', '    default:', '      cout << "Some other face." << endl;', '      break;', '  }'),
  prog('  char result = \'H\';', '  switch (result) {', '    case \'H\':', '      cout << "High!" << endl;', '      break;', '    case \'L\':', '      cout << "Low!" << endl;', '      break;', '  }'),
  prog('  int streak = 2;', '  switch (streak) {', '    case 2:', '      cout << "Gambling Addiction" << endl;', '      break;', '    default:', '      cout << "Still in control." << endl;', '  }'),
  prog('  int roll = 5;', '  int cooldown = 5;', '  switch (roll) {', '    case 1:', '      cooldown = 3;', '      break;', '  }', '  cout << cooldown << " s" << endl;', swap=[[3, 4]]),
  prog('  int roll = 1;', '  switch (roll) {', '    case 1:', '      cout << "One";', '    case 2:', '      cout << " falls into two" << endl;', '      break;', '  }'),
 ]},
 "all_in": {"topic": "C++ While Loop: while repeats a block as long as its condition is true", "variants": [
  prog('  int seconds = 10;', '  while (seconds > 0) {', '    seconds--;', '  }', '  cout << "Invincibility over." << endl;'),
  prog('  int hp = 100;', '  while (hp > 1) {', '    hp -= 33;', '  }', '  cout << "HP left: " << hp << endl;'),
  prog('  int chips = 1;', '  while (chips < 100) {', '    chips *= 2;', '  }', '  cout << chips << " chips" << endl;'),
  prog('  int i = 0;', '  while (i < 3) {', '    cout << "Bet " << i << endl;', '    i++;', '  }'),
  prog('  int left = 5;', '  do {', '    left--;', '  } while (left > 0);', '  cout << "Done: " << left << endl;'),
  prog('  bool buffed = false;', '  int tries = 0;', '  while (!buffed && tries < 3) {', '    tries++;', '  }', '  cout << tries << " tries" << endl;', swap=[[3, 4]]),
  prog('  int roll = 0;', '  do {', '    roll++;', '  } while (roll < 6);', '  cout << "Rolled a " << roll << endl;'),
  prog('  int pot = 0;', '  int round = 1;', '  while (round <= 4) {', '    pot += round;', '    round++;', '  }', '  cout << "Pot: " << pot << endl;', swap=[[3, 4]]),
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
