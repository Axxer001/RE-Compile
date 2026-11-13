extends Control

signal hack_completed()
signal closed()

enum ScreenMode { LOGIN, HACKTOOL, COMPLETED }

var current_mode: ScreenMode = ScreenMode.LOGIN
var current_question_index: int = 0
var has_password_lock: bool = false
var correct_password: String = "ccs2026"

# Python questions pool
var questions: Array[Dictionary] = [
	{
		"prompt": "# Complete the function to verify the encryption hash key:\ndef verify_key(key):\n    if len(key) == 8:\n        ______ True\n    return False",
		"solution": "return True",
		"hint": "Python keyword to send back a value"
	},
	{
		"prompt": "# Loop through memory buffer addresses 0 to 4:\naddresses = []\nfor i in ______(5):\n    addresses.append(i)",
		"solution": "range",
		"hint": "Built-in generator sequence in Python"
	},
	{
		"prompt": "# Check if system payload file exists in secure directory:\nimport os\nif os.path.______(path):\n    decrypt_file(path)",
		"solution": "exists",
		"hint": "os.path function checking presence of file"
	}
]

# UI references
@onready var login_screen: Control = $Panel/Screens/LoginScreen
@onready var hacktool_screen: Control = $Panel/Screens/HacktoolScreen
@onready var completed_screen: Control = $Panel/Screens/CompletedScreen

# Login UI
@onready var username_label: Label = $Panel/Screens/LoginScreen/UserBox/Username
@onready var password_input: LineEdit = $Panel/Screens/LoginScreen/UserBox/PasswordInput
@onready var login_btn: Button = $Panel/Screens/LoginScreen/UserBox/LoginBtn
@onready var login_feedback: Label = $Panel/Screens/LoginScreen/UserBox/Feedback

# Hacktool UI
@onready var q_indicator: Label = $Panel/Screens/HacktoolScreen/Header/QuestionIndicator
@onready var prompt_edit: TextEdit = $Panel/Screens/HacktoolScreen/VBox/PromptEdit
@onready var answer_input: LineEdit = $Panel/Screens/HacktoolScreen/VBox/HBox/AnswerInput
@onready var submit_btn: Button = $Panel/Screens/HacktoolScreen/VBox/HBox/SubmitBtn
@onready var hack_feedback: Label = $Panel/Screens/HacktoolScreen/VBox/Feedback

# Completed UI
@onready var close_btn: Button = $Panel/CloseBtn

func _ready() -> void:
	visible = false
	if login_btn: login_btn.pressed.connect(_on_login_attempt)
	if submit_btn: submit_btn.pressed.connect(_on_submit_answer)
	if close_btn: close_btn.pressed.connect(close_terminal)
	if password_input: password_input.text_submitted.connect(func(_t): _on_login_attempt())
	if answer_input: answer_input.text_submitted.connect(func(_t): _on_submit_answer())

func open_terminal(requires_password: bool = false) -> void:
	visible = true
	has_password_lock = requires_password
	current_question_index = 0
	
	if has_password_lock:
		_switch_screen(ScreenMode.LOGIN)
		password_input.text = ""
		password_input.visible = true
		login_feedback.text = "Password Required (Hint: ccs2026)"
		password_input.grab_focus()
	else:
		# Auto-login to desktop
		_switch_screen(ScreenMode.LOGIN)
		password_input.visible = false
		login_feedback.text = "Logging in as Guest Admin..."
		await get_tree().create_timer(0.6).timeout
		_boot_hacktool()

func _switch_screen(mode: ScreenMode) -> void:
	current_mode = mode
	login_screen.visible = (mode == ScreenMode.LOGIN)
	hacktool_screen.visible = (mode == ScreenMode.HACKTOOL)
	completed_screen.visible = (mode == ScreenMode.COMPLETED)

func _on_login_attempt() -> void:
	if has_password_lock:
		if password_input.text == correct_password:
			login_feedback.text = "Access Granted! Initializing HackTool..."
			login_feedback.modulate = Color(0.2, 1.0, 0.4)
			await get_tree().create_timer(0.5).timeout
			_boot_hacktool()
		else:
			login_feedback.text = "Incorrect Password! Try again."
			login_feedback.modulate = Color(1.0, 0.25, 0.25)
	else:
		_boot_hacktool()

func _boot_hacktool() -> void:
	_switch_screen(ScreenMode.HACKTOOL)
	_load_question(0)

func _load_question(idx: int) -> void:
	current_question_index = idx
	var q = questions[idx]
	q_indicator.text = "DECRYPTING NODE %d OF %d" % [idx + 1, questions.size()]
	prompt_edit.text = q["prompt"]
	answer_input.text = ""
	hack_feedback.text = "Fill in the blank syntax: " + q["hint"]
	hack_feedback.modulate = Color(0.7, 0.85, 1.0)
	answer_input.grab_focus()

func _on_submit_answer() -> void:
	var user_ans = answer_input.text.strip_edges()
	var expected = questions[current_question_index]["solution"].strip_edges()
	
	if user_ans == expected or expected in user_ans:
		hack_feedback.text = "[SYNTAX VALID] Node Decrypted!"
		hack_feedback.modulate = Color(0.2, 1.0, 0.4)
		await get_tree().create_timer(0.6).timeout
		
		if current_question_index + 1 < questions.size():
			_load_question(current_question_index + 1)
		else:
			_complete_hacking()
	else:
		hack_feedback.text = "[SYNTAX ERROR] Incorrect token. Try again!"
		hack_feedback.modulate = Color(1.0, 0.25, 0.25)

func _complete_hacking() -> void:
	_switch_screen(ScreenMode.COMPLETED)
	# Award research file to progression singleton
	var prog = get_node_or_null("/root/PlayerProgression")
	if prog and prog.has_method("add_research_file"):
		prog.add_research_file()
		
	hack_completed.emit()

func close_terminal() -> void:
	visible = false
	closed.emit()
