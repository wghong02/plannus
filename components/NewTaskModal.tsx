import React, { useState, useEffect, useRef } from "react";
import {
	Modal,
	View,
	Text,
	TouchableOpacity,
	StyleSheet,
	TextInput,
	FlatList,
	Dimensions,
	ScrollView,
	KeyboardAvoidingView,
	Platform,
	Alert,
	Keyboard,
} from "react-native";
import { formatTime } from "../utils/functions";
import TimePickerWheel from "./TimePickerWheel";
import DatePickerWheel from "./DatePickerWheel";
import { Task, SubTask, FrequencyPattern } from "../models";

interface NewTaskModalProps {
	visible: boolean;
	onCancel: () => void;
	onSave: (task: Omit<Task, "id">) => void;
	initialTitle?: string;
	initialStartTime?: string;
	initialEndTime?: string;
	initialNotes?: string;
	initialAllDay?: boolean;
	titleLabel?: string;
}

const FREQUENCY_PATTERNS: FrequencyPattern[] = [
	"none",
	"daily",
	"weekly",
	"monthly",
	"yearly",
	"custom",
];

// Custom Slider Component
const Slider = ({
	value,
	onValueChange,
	minimumValue = 0,
	maximumValue = 100,
	step = 1,
	onSliderStart,
	onSliderEnd,
}: {
	value: number;
	onValueChange: (value: number) => void;
	minimumValue?: number;
	maximumValue?: number;
	step?: number;
	onSliderStart?: () => void;
	onSliderEnd?: () => void;
}) => {
	const [sliderWidth, setSliderWidth] = useState(0);
	const [sliderLeft, setSliderLeft] = useState(0);

	const updateValue = (pageX: number) => {
		if (sliderWidth === 0) return;

		const relativeX = pageX - sliderLeft;
		const percentage = Math.max(0, Math.min(1, relativeX / sliderWidth));
		const newValue =
			Math.round(
				(percentage * (maximumValue - minimumValue) + minimumValue) / step
			) * step;
		onValueChange(newValue);
	};

	const handleStartShouldSetResponder = () => true;
	const handleMoveShouldSetResponder = () => true;

	const handleResponderGrant = (event: any) => {
		onSliderStart?.();
		updateValue(event.nativeEvent.pageX);
	};

	const handleResponderMove = (event: any) => {
		updateValue(event.nativeEvent.pageX);
	};

	const handleResponderRelease = () => {
		onSliderEnd?.();
	};

	const percentage = (value - minimumValue) / (maximumValue - minimumValue);

	return (
		<View style={styles.sliderContainer}>
			<View
				style={styles.sliderTrack}
				onLayout={(event) => {
					setSliderWidth(event.nativeEvent.layout.width);
					event.target.measure((x, y, width, height, pageX, pageY) => {
						setSliderLeft(pageX);
					});
				}}
				onStartShouldSetResponder={handleStartShouldSetResponder}
				onMoveShouldSetResponder={handleMoveShouldSetResponder}
				onResponderGrant={handleResponderGrant}
				onResponderMove={handleResponderMove}
				onResponderRelease={handleResponderRelease}
			>
				<View style={[styles.sliderFill, { width: `${percentage * 100}%` }]} />
				<View style={[styles.sliderThumb, { left: `${percentage * 100}%` }]} />
			</View>
			<Text style={styles.sliderValue}>{value}</Text>
		</View>
	);
};

export default function NewTaskModal({
	visible,
	onCancel,
	onSave,
	initialTitle = "New Task",
	initialStartTime = "08:00",
	initialEndTime = "09:00",
	initialNotes = "",
	initialAllDay = false,
}: NewTaskModalProps) {
	const [title, setTitle] = useState(initialTitle);
	const [startTime, setStartTime] = useState(initialStartTime);
	const [endTime, setEndTime] = useState(initialEndTime);
	const [notes, setNotes] = useState(initialNotes);
	const [allDay, setAllDay] = useState(initialAllDay);
	const [showStartTimePicker, setShowStartTimePicker] = useState(false);
	const [showEndTimePicker, setShowEndTimePicker] = useState(false);

	// Task-specific fields
	const [priorityRating, setPriorityRating] = useState(50);
	const [performanceRating, setPerformanceRating] = useState(50);
	const [startDate, setStartDate] = useState(
		new Date().toISOString().split("T")[0]
	);
	const [endDate, setEndDate] = useState(
		new Date().toISOString().split("T")[0]
	);
	const [frequencyPattern, setFrequencyPattern] =
		useState<FrequencyPattern>("none");
	const [frequencyCount, setFrequencyCount] = useState(1);
	const [recurring, setRecurring] = useState(false);
	const [estimatedDuration, setEstimatedDuration] = useState("");
	const [actualDuration, setActualDuration] = useState("");
	const [types, setTypes] = useState<string[]>([]);
	const [newType, setNewType] = useState("");

	// Date picker states
	const [showStartDatePicker, setShowStartDatePicker] = useState(false);
	const [showEndDatePicker, setShowEndDatePicker] = useState(false);

	// Subtasks
	const [subTasks, setSubTasks] = useState<
		Omit<SubTask, "id" | "parentTaskId" | "order">[]
	>([]);
	const [newSubTaskTitle, setNewSubTaskTitle] = useState("");
	const [newSubTaskNotes, setNewSubTaskNotes] = useState("");

	// Scroll control
	const [isSliderActive, setIsSliderActive] = useState(false);

	// Keyboard handling
	const [keyboardPadding, setKeyboardPadding] = useState(0);
	const [currentScrollY, setCurrentScrollY] = useState(0);
	const scrollViewRef = useRef<ScrollView>(null);

	useEffect(() => {
		const keyboardDidShowListener = Keyboard.addListener(
			"keyboardDidShow",
			() => {
				setKeyboardPadding(40);
				// Scroll down 80px from current position when keyboard appears
				setTimeout(() => {
					scrollViewRef.current?.scrollTo({
						y: currentScrollY + 80,
						animated: true,
					});
				}, 100);
			}
		);
		const keyboardDidHideListener = Keyboard.addListener(
			"keyboardDidHide",
			() => {
				setKeyboardPadding(0);
				// Scroll back to original position when keyboard disappears
				scrollViewRef.current?.scrollTo({
					y: currentScrollY,
					animated: true,
				});
			}
		);

		return () => {
			keyboardDidShowListener?.remove();
			keyboardDidHideListener?.remove();
		};
	}, [currentScrollY]);

	React.useEffect(() => {
		if (visible) {
			setTitle(initialTitle);
			setStartTime(initialStartTime);
			setEndTime(initialEndTime);
			setNotes(initialNotes);
			setAllDay(initialAllDay);
			// Reset task-specific fields
			setPriorityRating(50);
			setPerformanceRating(50);
			setStartDate(new Date().toISOString().split("T")[0]);
			setEndDate(new Date().toISOString().split("T")[0]);
			setFrequencyPattern("none");
			setFrequencyCount(1);
			setRecurring(false);
			setEstimatedDuration("");
			setActualDuration("");
			setTypes([]);
			setSubTasks([]);
			setShowStartDatePicker(false);
			setShowEndDatePicker(false);
		}
	}, [
		visible,
		initialTitle,
		initialStartTime,
		initialEndTime,
		initialNotes,
		initialAllDay,
	]);

	const handleStartTimePress = () => {
		setShowEndTimePicker(false);
		setShowStartTimePicker((v) => !v);
	};

	const handleEndTimePress = () => {
		setShowStartTimePicker(false);
		setShowEndTimePicker((v) => !v);
	};

	const handleStartDatePress = () => {
		setShowEndDatePicker(false);
		setShowStartDatePicker((v) => !v);
	};

	const handleEndDatePress = () => {
		setShowStartDatePicker(false);
		setShowEndDatePicker((v) => !v);
	};

	const handleAllDayToggle = () => {
		setAllDay(!allDay);
		if (!allDay) {
			setStartTime("");
			setEndTime("");
		} else {
			setStartTime("08:00");
			setEndTime("09:00");
		}
		setShowStartTimePicker(false);
		setShowEndTimePicker(false);
	};

	const handleRecurringToggle = () => {
		setRecurring(!recurring);
		if (!recurring) {
			setFrequencyPattern("daily");
		} else {
			setFrequencyPattern("none");
		}
	};

	const addSubTask = () => {
		if (newSubTaskTitle.trim()) {
			const newSubTask: Omit<SubTask, "id" | "parentTaskId" | "order"> = {
				title: newSubTaskTitle.trim(),
				notes: newSubTaskNotes.trim(),
				priorityRating: 50,
				performanceRating: 50,
				completed: false,
				date: startDate,
			};
			setSubTasks([...subTasks, newSubTask]);
			setNewSubTaskTitle("");
			setNewSubTaskNotes("");
		}
	};

	const removeSubTask = (index: number) => {
		setSubTasks(subTasks.filter((_, i) => i !== index));
	};

	const addType = () => {
		if (newType.trim() && !types.includes(newType.trim())) {
			setTypes([...types, newType.trim()]);
			setNewType("");
		}
	};

	const removeType = (typeToRemove: string) => {
		setTypes(types.filter((type) => type !== typeToRemove));
	};

	const handleSave = () => {
		if (!title.trim()) {
			Alert.alert("Error", "Please enter a task title");
			return;
		}

		const task: Omit<Task, "id"> = {
			title: title.trim(),
			allDay,
			startTime: allDay ? undefined : startTime,
			endTime: allDay ? undefined : endTime,
			notes: notes.trim(),
			priorityRating,
			performanceRating,
			completed: false,
			startDate,
			endDate,
			frequencyPattern,
			frequencyCount,
			subTasks: subTasks.map((subTask, index) => ({
				...subTask,
				id: `temp-${index}`,
				parentTaskId: "temp-parent",
				order: index,
			})),
			types: types.length > 0 ? types : undefined,
			estimatedDuration: estimatedDuration
				? parseInt(estimatedDuration)
				: undefined,
			actualDuration: actualDuration ? parseInt(actualDuration) : undefined,
			recurring,
		};

		onSave(task);
	};

	const renderSubTask = ({
		item,
		index,
	}: {
		item: Omit<SubTask, "id" | "parentTaskId" | "order">;
		index: number;
	}) => (
		<View style={styles.subTaskItem}>
			<View style={styles.subTaskContent}>
				<Text style={styles.subTaskTitle}>{item.title}</Text>
				{item.notes && <Text style={styles.subTaskNotes}>{item.notes}</Text>}
			</View>
			<TouchableOpacity
				style={styles.removeButton}
				onPress={() => removeSubTask(index)}
			>
				<Text style={styles.removeButtonText}>×</Text>
			</TouchableOpacity>
		</View>
	);

	const handleSliderStart = () => {
		setIsSliderActive(true);
	};

	const handleSliderEnd = () => {
		setIsSliderActive(false);
	};

	return (
		<Modal visible={visible} transparent animationType="slide">
			<View style={styles.overlay}>
				<View style={styles.bottomSheet}>
					<View style={styles.header}>
						<TouchableOpacity onPress={onCancel} style={styles.headerButton}>
							<Text style={styles.cancelText}>Cancel</Text>
						</TouchableOpacity>
						<Text style={styles.headerTitle}>New Task</Text>
						<TouchableOpacity onPress={handleSave} style={styles.headerButton}>
							<Text style={styles.saveText}>Save</Text>
						</TouchableOpacity>
					</View>

					<KeyboardAvoidingView
						behavior={Platform.OS === "ios" ? "padding" : undefined}
						style={{ flex: 1 }}
					>
						<ScrollView
							contentContainerStyle={[
								styles.content,
								{ paddingBottom: 80 + keyboardPadding },
							]}
							scrollEnabled={!isSliderActive}
							ref={scrollViewRef}
							onScroll={(event) => {
								setCurrentScrollY(event.nativeEvent.contentOffset.y);
							}}
							scrollEventThrottle={16}
						>
							{/* Section 1: Task Description */}
							<Text style={styles.sectionLabel}>Task Description</Text>
							<TextInput
								style={styles.input}
								placeholder="Task title"
								placeholderTextColor="#999"
								value={title}
								onChangeText={setTitle}
							/>

							{/* Section 2: Priority and Performance */}
							<View style={styles.ratingContainer}>
								<View style={styles.ratingItem}>
									<Text style={styles.sectionLabel}>Priority Rating</Text>
									<Slider
										value={priorityRating}
										onValueChange={setPriorityRating}
										minimumValue={0}
										maximumValue={100}
										onSliderStart={handleSliderStart}
										onSliderEnd={handleSliderEnd}
									/>
								</View>

								<View style={styles.ratingItem}>
									<Text style={styles.sectionLabel}>Performance Rating</Text>
									<Slider
										value={performanceRating}
										onValueChange={setPerformanceRating}
										minimumValue={0}
										maximumValue={100}
										onSliderStart={handleSliderStart}
										onSliderEnd={handleSliderEnd}
									/>
								</View>
							</View>

							{/* Section 3: Dates */}
							<Text style={styles.sectionLabel}>Start Date</Text>
							<TouchableOpacity
								style={styles.dateRow}
								onPress={handleStartDatePress}
							>
								<Text style={styles.dateRowText}>
									{new Date(startDate).toLocaleDateString()}
								</Text>
								<Text style={styles.dateRowIcon}>
									{showStartDatePicker ? "▲" : "▼"}
								</Text>
							</TouchableOpacity>
							{showStartDatePicker && (
								<DatePickerWheel date={startDate} onDateChange={setStartDate} />
							)}

							<Text style={styles.sectionLabel}>End Date</Text>
							<TouchableOpacity
								style={styles.dateRow}
								onPress={handleEndDatePress}
							>
								<Text style={styles.dateRowText}>
									{new Date(endDate).toLocaleDateString()}
								</Text>
								<Text style={styles.dateRowIcon}>
									{showEndDatePicker ? "▲" : "▼"}
								</Text>
							</TouchableOpacity>
							{showEndDatePicker && (
								<DatePickerWheel date={endDate} onDateChange={setEndDate} />
							)}

							{/* Section 4: Time Pickers */}
							<View style={styles.allDayContainer}>
								<Text style={styles.sectionLabel}>All Day</Text>
								<TouchableOpacity
									style={[styles.checkbox, allDay && styles.checkboxChecked]}
									onPress={handleAllDayToggle}
								>
									{allDay && <Text style={styles.checkmark}>✓</Text>}
								</TouchableOpacity>
							</View>

							{!allDay && (
								<>
									<Text style={styles.sectionLabel}>Start Time</Text>
									<TouchableOpacity
										style={styles.timeRow}
										onPress={handleStartTimePress}
									>
										<Text style={styles.timeRowText}>
											{formatTime(startTime)}
										</Text>
										<Text style={styles.timeRowIcon}>
											{showStartTimePicker ? "▲" : "▼"}
										</Text>
									</TouchableOpacity>
									{showStartTimePicker && (
										<TimePickerWheel
											time={startTime}
											onTimeChange={setStartTime}
										/>
									)}

									<Text style={styles.sectionLabel}>End Time</Text>
									<TouchableOpacity
										style={styles.timeRow}
										onPress={handleEndTimePress}
									>
										<Text style={styles.timeRowText}>
											{formatTime(endTime)}
										</Text>
										<Text style={styles.timeRowIcon}>
											{showEndTimePicker ? "▲" : "▼"}
										</Text>
									</TouchableOpacity>
									{showEndTimePicker && (
										<TimePickerWheel time={endTime} onTimeChange={setEndTime} />
									)}
								</>
							)}

							{/* Section 5: Recurring */}
							<View style={styles.allDayContainer}>
								<Text style={styles.sectionLabel}>Recurring Task</Text>
								<TouchableOpacity
									style={[styles.checkbox, recurring && styles.checkboxChecked]}
									onPress={handleRecurringToggle}
								>
									{recurring && <Text style={styles.checkmark}>✓</Text>}
								</TouchableOpacity>
							</View>

							{recurring && (
								<>
									<Text style={styles.sectionLabel}>Frequency Pattern</Text>
									<View style={styles.frequencyContainer}>
										{FREQUENCY_PATTERNS.map((pattern) => (
											<TouchableOpacity
												key={pattern}
												style={[
													styles.frequencyButton,
													frequencyPattern === pattern &&
														styles.frequencyButtonSelected,
												]}
												onPress={() => setFrequencyPattern(pattern)}
											>
												<Text
													style={[
														styles.frequencyButtonText,
														frequencyPattern === pattern &&
															styles.frequencyButtonTextSelected,
													]}
												>
													{pattern.charAt(0).toUpperCase() + pattern.slice(1)}
												</Text>
											</TouchableOpacity>
										))}
									</View>

									<Text style={styles.sectionLabel}>Frequency Count</Text>
									<TextInput
										style={styles.input}
										placeholder="1"
										placeholderTextColor="#999"
										value={frequencyCount.toString()}
										onChangeText={(text) =>
											setFrequencyCount(parseInt(text) || 1)
										}
										keyboardType="numeric"
									/>
								</>
							)}

							{/* Section 6: Duration */}
							<Text style={styles.sectionLabel}>
								Estimated Duration (minutes)
							</Text>
							<TextInput
								style={styles.input}
								placeholder="60"
								placeholderTextColor="#999"
								value={estimatedDuration}
								onChangeText={setEstimatedDuration}
								keyboardType="numeric"
							/>

							{/* Section 7: Types */}
							<Text style={styles.sectionLabel}>Task Types</Text>
							<View style={styles.typeInputContainer}>
								<TextInput
									style={[styles.input, styles.typeInput]}
									placeholder="Add task type..."
									placeholderTextColor="#999"
									value={newType}
									onChangeText={setNewType}
								/>
								<TouchableOpacity style={styles.addButton} onPress={addType}>
									<Text style={styles.addButtonText}>Add</Text>
								</TouchableOpacity>
							</View>
							{types.length > 0 && (
								<View style={styles.typesContainer}>
									{types.map((type, index) => (
										<TouchableOpacity
											key={index}
											style={styles.typeTag}
											onPress={() => removeType(type)}
										>
											<Text style={styles.typeTagText}>{type}</Text>
											<Text style={styles.typeTagRemove}>×</Text>
										</TouchableOpacity>
									))}
								</View>
							)}

							{/* Section 8: Subtasks */}
							<Text style={styles.sectionLabel}>Subtasks</Text>
							<View style={styles.subTaskInputContainer}>
								<TextInput
									style={[styles.input, styles.subTaskTitleInput]}
									placeholder="Subtask title..."
									placeholderTextColor="#999"
									value={newSubTaskTitle}
									onChangeText={setNewSubTaskTitle}
								/>
								<TextInput
									style={[styles.input, styles.subTaskNotesInput]}
									placeholder="Subtask notes..."
									placeholderTextColor="#999"
									value={newSubTaskNotes}
									onChangeText={setNewSubTaskNotes}
								/>
								<TouchableOpacity style={styles.addButton} onPress={addSubTask}>
									<Text style={styles.addButtonText}>Add</Text>
								</TouchableOpacity>
							</View>
							{subTasks.length > 0 && (
								<FlatList
									data={subTasks}
									renderItem={renderSubTask}
									keyExtractor={(_, index) => index.toString()}
									scrollEnabled={false}
								/>
							)}

							{/* Section 9: Notes */}
							<Text style={styles.sectionLabel}>Notes</Text>
							<TextInput
								style={styles.notesInput}
								placeholder="Add notes..."
								placeholderTextColor="#999"
								value={notes}
								onChangeText={setNotes}
								multiline
								numberOfLines={4}
							/>
						</ScrollView>
					</KeyboardAvoidingView>
				</View>
			</View>
		</Modal>
	);
}

const { height: SCREEN_HEIGHT } = Dimensions.get("window");

const styles = StyleSheet.create({
	overlay: {
		flex: 1,
		backgroundColor: "rgba(0,0,0,0.5)",
		justifyContent: "flex-end",
		alignItems: "center",
	},
	bottomSheet: {
		width: "100%",
		maxWidth: 600,
		height: SCREEN_HEIGHT * 0.88,
		backgroundColor: "white",
		borderTopLeftRadius: 24,
		borderTopRightRadius: 24,
		overflow: "hidden",
	},
	content: {
		padding: 20,
		paddingBottom: 80,
	},
	header: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		marginBottom: 16,
		paddingTop: 20,
		paddingLeft: 20,
		paddingRight: 20,
	},
	headerButton: {
		padding: 8,
	},
	headerTitle: {
		fontSize: 18,
		fontWeight: "bold",
	},
	cancelText: {
		color: "#888",
		fontSize: 16,
	},
	saveText: {
		color: "#007AFF",
		fontSize: 16,
		fontWeight: "bold",
	},
	sectionLabel: {
		fontWeight: "bold",
		marginBottom: 4,
		marginTop: 8,
	},
	input: {
		borderColor: "#ccc",
		borderWidth: 1,
		borderRadius: 6,
		padding: 10,
		marginBottom: 8,
		fontSize: 16,
	},
	timeRow: {
		flexDirection: "row",
		alignItems: "center",
		borderColor: "#ccc",
		borderWidth: 1,
		borderRadius: 6,
		padding: 12,
		marginBottom: 8,
		justifyContent: "space-between",
	},
	timeRowText: {
		fontSize: 16,
	},
	timeRowIcon: {
		fontSize: 16,
		marginLeft: 8,
	},
	dateRow: {
		flexDirection: "row",
		alignItems: "center",
		borderColor: "#ccc",
		borderWidth: 1,
		borderRadius: 6,
		padding: 12,
		marginBottom: 8,
		justifyContent: "space-between",
	},
	dateRowText: {
		fontSize: 16,
	},
	dateRowIcon: {
		fontSize: 16,
		marginLeft: 8,
	},
	notesInput: {
		borderColor: "#ccc",
		borderWidth: 1,
		borderRadius: 6,
		padding: 10,
		fontSize: 16,
		minHeight: 60,
		textAlignVertical: "top",
	},
	allDayContainer: {
		flexDirection: "row",
		alignItems: "center",
		marginTop: 8,
		marginBottom: 8,
	},
	checkbox: {
		borderColor: "#ccc",
		borderWidth: 1,
		borderRadius: 6,
		padding: 12,
		marginLeft: 8,
	},
	checkboxChecked: {
		backgroundColor: "#007AFF",
		padding: 4,
	},
	checkmark: {
		fontSize: 16,
		fontWeight: "bold",
		color: "white",
	},
	ratingContainer: {
		marginBottom: 16,
	},
	ratingItem: {
		marginBottom: 12,
	},
	sliderContainer: {
		flexDirection: "row",
		alignItems: "center",
		marginTop: 4,
	},
	sliderTrack: {
		flex: 1,
		height: 4,
		backgroundColor: "#e0e0e0",
		borderRadius: 2,
		position: "relative",
		marginRight: 16,
	},
	sliderTrackTouch: {
		position: "absolute",
		top: 0,
		left: 0,
		width: "100%",
		height: "100%",
	},
	sliderFill: {
		height: "100%",
		backgroundColor: "#007AFF",
		borderRadius: 2,
		position: "absolute",
		top: 0,
		left: 0,
	},
	sliderThumb: {
		position: "absolute",
		top: -8,
		width: 20,
		height: 20,
		backgroundColor: "#007AFF",
		borderRadius: 10,
		borderWidth: 2,
		borderColor: "white",
		shadowColor: "#000",
		shadowOffset: {
			width: 0,
			height: 2,
		},
		shadowOpacity: 0.25,
		shadowRadius: 3.84,
		elevation: 5,
		transform: [{ translateX: -10 }],
	},
	sliderValue: {
		fontSize: 16,
		fontWeight: "bold",
		color: "#007AFF",
		minWidth: 30,
		textAlign: "center",
	},
	frequencyContainer: {
		flexDirection: "row",
		flexWrap: "wrap",
		marginTop: 4,
	},
	frequencyButton: {
		borderColor: "#ccc",
		borderWidth: 1,
		borderRadius: 6,
		padding: 8,
		marginRight: 8,
		marginBottom: 8,
	},
	frequencyButtonSelected: {
		backgroundColor: "#007AFF",
		borderColor: "#007AFF",
	},
	frequencyButtonText: {
		fontSize: 14,
		color: "#333",
	},
	frequencyButtonTextSelected: {
		color: "white",
		fontWeight: "bold",
	},
	typeInputContainer: {
		flexDirection: "row",
		alignItems: "center",
		marginBottom: 8,
	},
	typeInput: {
		flex: 1,
		marginBottom: 0,
		marginRight: 8,
	},
	addButton: {
		backgroundColor: "#007AFF",
		padding: 10,
		borderRadius: 6,
	},
	addButtonText: {
		color: "white",
		fontWeight: "bold",
	},
	typesContainer: {
		flexDirection: "row",
		flexWrap: "wrap",
		marginBottom: 8,
	},
	typeTag: {
		backgroundColor: "#E3F2FD",
		borderRadius: 16,
		paddingHorizontal: 12,
		paddingVertical: 6,
		marginRight: 8,
		marginBottom: 8,
		flexDirection: "row",
		alignItems: "center",
	},
	typeTagText: {
		color: "#1976D2",
		fontSize: 14,
		marginRight: 4,
	},
	typeTagRemove: {
		color: "#1976D2",
		fontSize: 16,
		fontWeight: "bold",
	},
	subTaskInputContainer: {
		marginBottom: 8,
	},
	subTaskTitleInput: {
		marginBottom: 4,
	},
	subTaskNotesInput: {
		marginBottom: 4,
	},
	subTaskItem: {
		flexDirection: "row",
		alignItems: "center",
		backgroundColor: "#f8f9fa",
		borderRadius: 6,
		padding: 12,
		marginBottom: 8,
	},
	subTaskContent: {
		flex: 1,
	},
	subTaskTitle: {
		fontSize: 16,
		fontWeight: "500",
		marginBottom: 2,
	},
	subTaskNotes: {
		fontSize: 14,
		color: "#666",
	},
	removeButton: {
		backgroundColor: "#ff4444",
		borderRadius: 12,
		width: 24,
		height: 24,
		alignItems: "center",
		justifyContent: "center",
		marginLeft: 8,
	},
	removeButtonText: {
		color: "white",
		fontSize: 16,
		fontWeight: "bold",
	},
});
