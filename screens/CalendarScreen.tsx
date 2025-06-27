import React, { useEffect, useState } from "react";
import {
	View,
	TextInput,
	Button,
	Text,
	TouchableOpacity,
	Alert,
	FlatList,
	KeyboardAvoidingView,
	Platform,
	TouchableWithoutFeedback,
	Keyboard,
} from "react-native";
import { Calendar } from "react-native-calendars";
import { StyleSheet } from "react-native";
import NewTaskModal from "../components/NewTaskModal";
import { loadTasks, saveTasks, deleteTask } from "../utils/taskStorage";
import type { Task, TaskMap } from "../models";

const STORAGE_KEY = "task";

export default function CalendarScreen() {
	const [selectedDate, setSelectedDate] = useState("");
	const [task, setTask] = useState<TaskMap>({});
	const [editIndex, setEditIndex] = useState<number | null>(null);
	const [showTaskModal, setShowTaskModal] = useState(false);
	const [modalInitialTitle, setModalInitialTitle] = useState("");
	const [modalInitialStartTime, setModalInitialStartTime] = useState("");
	const [modalInitialEndTime, setModalInitialEndTime] = useState("");
	const [modalInitialNotes, setModalInitialNotes] = useState("");
	const [modalInitialAllDay, setModalInitialAllDay] = useState(false);

	// Load from AsyncStorage
	useEffect(() => {
		(async () => {
			const loaded = await loadTasks();
			setTask(loaded);
		})();
	}, []);

	// Reset modal state when modal closes
	useEffect(() => {
		if (!showTaskModal) {
			setModalInitialTitle("New Task");
			setModalInitialStartTime("08:00");
			setModalInitialEndTime("09:00");
			setModalInitialNotes("");
			setModalInitialAllDay(false);
		}
	}, [showTaskModal]);

	const handleAddTask = () => {
		setEditIndex(null);
		setShowTaskModal(true);
	};

	const handleEdit = (index: number) => {
		const item = task[selectedDate][index];
		setEditIndex(index);
		setModalInitialTitle(item.title);
		setModalInitialStartTime(item.startTime || "");
		setModalInitialEndTime(item.endTime || "");
		setModalInitialNotes(item.notes || "");
		setModalInitialAllDay(item.allDay || false);
		setShowTaskModal(true);
	};

	const handleSaveTask = async (
		title: string,
		startTime: string,
		endTime: string,
		notes: string,
		allDay: boolean
	) => {
		if (!title) {
			setShowTaskModal(false);
			return;
		}
		const items = task[selectedDate] || [];
		let updatedItems: Task[];
		if (editIndex !== null) {
			updatedItems = [...items];
			updatedItems[editIndex] = {
				id: updatedItems[editIndex].id,
				title,
				allDay,
				startTime,
				endTime,
				notes,
			};
		} else {
			const newTask: Task = {
				id: Date.now().toString(),
				title,
				allDay,
				startTime,
				endTime,
				notes,
			};
			updatedItems = [...items, newTask];
		}
		// Sort by start time if available, otherwise by title
		updatedItems.sort((a, b) => {
			if (a.startTime && b.startTime) {
				return a.startTime.localeCompare(b.startTime);
			}
			return a.title.localeCompare(b.title);
		});
		const updatedTask = { ...task, [selectedDate]: updatedItems };

		try {
			await saveTasks(updatedTask);
			setTask(updatedTask);
			setShowTaskModal(false);
			setEditIndex(null);
		} catch (error) {
			console.error("Failed to save task:", error);
			// You might want to show an alert here to inform the user
		}
	};

	const handleDelete = (index: number) => {
		Alert.alert("Delete Task", "Are you sure?", [
			{ text: "Cancel", style: "cancel" },
			{
				text: "Delete",
				style: "destructive",
				onPress: async () => {
					const updated = await deleteTask(task, selectedDate, index);
					setTask(updated);
					setEditIndex(null);
				},
			},
		]);
	};

	const formatTime = (time: string) => {
		const [hours, minutes] = time.split(":");
		const hour = parseInt(hours);
		const ampm = hour >= 12 ? "PM" : "AM";
		const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
		return `${displayHour}:${minutes} ${ampm}`;
	};

	const taskItems = task[selectedDate] || [];

	return (
		<>
			<TouchableWithoutFeedback onPress={Keyboard.dismiss}>
				<KeyboardAvoidingView
					style={styles.container}
					behavior={Platform.OS === "ios" ? "padding" : "height"}
					keyboardVerticalOffset={80}
				>
					<Calendar
						onDayPress={(day) => setSelectedDate(day.dateString)}
						markedDates={{
							[selectedDate]: { selected: true, selectedColor: "blue" },
						}}
					/>

					{selectedDate ? (
						<View style={styles.taskContainer}>
							<Text style={styles.taskTitle}>Tasks for {selectedDate}</Text>

							<FlatList
								data={taskItems}
								keyExtractor={(item) => item.id}
								ListEmptyComponent={
									<Text style={styles.noItems}>No tasks yet</Text>
								}
								renderItem={({ item, index }) => (
									<View style={styles.taskItem}>
										<TouchableOpacity
											style={styles.itemTextContainer}
											onPress={() => handleEdit(index)}
										>
											<Text style={styles.taskItemTitle}>{item.title}</Text>
										</TouchableOpacity>
										<View style={styles.taskTimeContainer}>
											{item.startTime && (
												<Text style={styles.taskTime}>
													{formatTime(item.startTime)}
												</Text>
											)}
											{item.endTime && (
												<Text style={styles.taskEndTime}>
													{formatTime(item.endTime)}
												</Text>
											)}
										</View>
										<TouchableOpacity onPress={() => handleDelete(index)}>
											<Text style={styles.deleteButton}>✕</Text>
										</TouchableOpacity>
									</View>
								)}
								style={styles.flatList}
							/>

							<TouchableOpacity
								style={styles.addButton}
								onPress={handleAddTask}
							>
								<Text style={styles.addButtonText}>+ Add Task</Text>
							</TouchableOpacity>
						</View>
					) : (
						<Text style={styles.selectPrompt}>Select a date to view tasks</Text>
					)}
				</KeyboardAvoidingView>
			</TouchableWithoutFeedback>

			<NewTaskModal
				visible={showTaskModal}
				onCancel={() => setShowTaskModal(false)}
				onSave={handleSaveTask}
				initialTitle={modalInitialTitle}
				initialStartTime={modalInitialStartTime}
				initialEndTime={modalInitialEndTime}
				initialNotes={modalInitialNotes}
				initialAllDay={modalInitialAllDay}
			/>
		</>
	);
}

const styles = StyleSheet.create({
	container: { flex: 1, backgroundColor: "white" },
	taskContainer: { flex: 1, padding: 16 },
	taskTitle: { fontSize: 16, fontWeight: "bold", marginBottom: 8 },
	taskItem: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		padding: 12,
		backgroundColor: "#f3f4f6",
		borderRadius: 8,
		marginBottom: 8,
	},
	itemTextContainer: { flex: 1, marginRight: 10 },
	deleteButton: {
		fontSize: 16,
		color: "red",
		paddingHorizontal: 8,
	},
	noItems: {
		fontStyle: "italic",
		color: "#888",
		padding: 12,
	},
	flatList: {
		flex: 1,
		marginBottom: 12,
	},
	selectPrompt: {
		textAlign: "center",
		marginTop: 40,
		color: "#888",
		fontSize: 16,
	},
	taskTimeContainer: {
		width: 80,
		padding: 8,
		backgroundColor: "#f3f4f6",
		borderRadius: 6,
	},
	taskTime: {
		fontSize: 14,
		fontWeight: "bold",
	},
	taskItemTitle: {
		fontSize: 14,
		fontWeight: "bold",
	},
	addButton: {
		marginTop: 16,
		backgroundColor: "#007AFF",
		paddingVertical: 12,
		borderRadius: 8,
		alignItems: "center",
	},
	addButtonText: {
		color: "white",
		fontSize: 16,
		fontWeight: "bold",
	},
	taskEndTime: {
		fontSize: 12,
		color: "#888",
	},
});
