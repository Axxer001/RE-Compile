extends RefCounted
# Puzzle content for the two hacking terminals (original, campus-themed).
# Answers are fixed per career by its seed, so a note read on night 1 stays
# true on night 3, but different careers get different answers.

const LAB_PREFIX := "CCS-"

# Lab 2 admin: the temporary password written on the classroom whiteboard.
static func lab_password(seed: int) -> String:
	return LAB_PREFIX + str(1000 + absi(seed) % 9000)

# Faculty office: a grading script with one wrong line. {title, lines,
# options (line numbers offered on keys 1-3), answer (index into options), hint}
const OFFICE_VARIANTS := [
	{
		"title": "grades.py  -  class average is always the last score",
		"lines": ["def average(scores):", "    total = 0", "    for s in scores:", "        total = s", "    return total / len(scores)"],
		"options": [2, 4, 5], "answer": 1,
		"hint": "The loop replaces the total instead of adding each score to it.",
	},
	{
		"title": "grades.py  -  every student is marked as passing",
		"lines": ["def passed(score):", "    if score >= 75:", "        return True", "    return True"],
		"options": [2, 3, 4], "answer": 2,
		"hint": "Look at what the function returns when the score is too low.",
	},
	{
		"title": "attendance.py  -  absences are counted wrong",
		"lines": ["def absences(days):", "    count = 0", "    for d in days:", "        if d == \"present\":", "            count += 1", "    return count"],
		"options": [2, 4, 6], "answer": 1,
		"hint": "It is counting the days the student showed up.",
	},
]

static func office_puzzle(seed: int) -> Dictionary:
	return OFFICE_VARIANTS[absi(seed) % OFFICE_VARIANTS.size()]

# Terminal definitions: what each one pays out when solved.
const TERMINALS := {
	"terminal_lab": {
		"label": "LAB 2 ADMIN", "kind": "password", "research": "research_lab", "unlock": "intel",
		"journal": ["lab_hacked", "Lab 2 server logs", "Someone copied the lecturer's sample data to the lab server at 23:40. The camera feeds and room inventory are now on your phone map."],
	},
	"terminal_office": {
		"label": "FACULTY PC", "kind": "choice", "research": "research_office", "unlock": "",
		"journal": ["office_hacked", "Lecturer's research folder", "Field notes on the infection: subjects react to sound, ignore anyone who stays crouched and quiet, and cannot fit through low gaps."],
	},
}
const MAX_ATTEMPTS := 3
const LOCKOUT_S := 15.0
const ALARM_RADIUS := 10.0 # metres; a lockout is loud

# Notes the player can read (E): {id, title, text (may use {password}), unlock}
const NOTES := {
	"note_whiteboard": {"title": "Whiteboard, Classroom 104", "text": "LAB 2 ADMIN - temp password {password}\nchange after finals!! - IT office", "unlock": ""},
	"note_grading": {"title": "Sticky note, Computer Lab 2", "text": "Dr. Ramos: your grading script is broken again. Read it line by line before you submit anything. Hints are on your phone now.", "unlock": "hints"},
	# Story notes (journal only): what happened to the College, in the staff's words.
	"note_bulletin": {"title": "Bulletin board, east corridor", "text": "ADVISORY: All evening classes in the College of Computing Studies are suspended until further notice. Students reporting fever, confusion or sensitivity to light must proceed to the University Health Services. Do NOT use the service corridor. - Office of the Dean", "unlock": ""},
	"note_memo": {"title": "Memo on the faculty office cabinet", "text": "To Dr. Ramos: the samples from the field study must leave campus TONIGHT. The contractor's van will wait at the service exit. Copy your research to the lab server and to your office PC in case one of them fails. Tell no one. - D.", "unlock": ""},
	"note_lablog": {"title": "Sign-out log, Computer Lab 2", "text": "23:05 J. Santos - left. 23:12 K. Lim - left. 23:40 Dr. Ramos - [no sign-out]. Someone wrote underneath in red ink: SHE NEVER CAME OUT.", "unlock": ""},
}

static func note_text(id: String, seed: int) -> String:
	return String(NOTES[id].text).replace("{password}", lab_password(seed))
