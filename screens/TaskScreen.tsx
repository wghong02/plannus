import React, { useEffect, useState } from "react";
import {
	Text,
	View,
	TextInput,
	StyleSheet,
	FlatList,
	Button,
	KeyboardAvoidingView,
	Platform,
	Alert,
	TouchableOpacity,
} from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import {
	GestureHandlerRootView,
	Swipeable,
} from "react-native-gesture-handler";
import NewTaskModal from "../components/NewTaskModal";
import { Task } from "../models";

const STORAGE_KEY = "@tasks_list";

export default function TaskScreen() {
	const [tasks, setTasks] = useState<Task[]>([]);
	const [modalVisible, setModalVisible] = useState(false);

	useEffect(() => {
		loadTasks();
	}, []);

	const loadTasks = async () => {
		try {
			const storedTasks = await AsyncStorage.getItem(STORAGE_KEY);
			if (storedTasks) {
				setTasks(JSON.parse(storedTasks));
			}
		} catch (error) {
			console.error("Error loading tasks:", error);
		}
	};

	const saveTasks = async (newTasks: Task[]) => {
		try {
			await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(newTasks));
		} catch (error) {
			console.error("Error saving tasks:", error);
		}
	};

	const handleAddTask = (taskData: Omit<Task, "id">) => {
		const newTask: Task = {
			...taskData,
			id: Date.now().toString(),
		};
		const updatedTasks = [...tasks, newTask];
		setTasks(updatedTasks);
		saveTasks(updatedTasks);
		setModalVisible(false);
	};

	const handleDeleteTask = (taskId: string) => {
		Alert.alert("Delete Task", "Are you sure you want to delete this task?", [
			{ text: "Cancel", style: "cancel" },
			{
				text: "Delete",
				style: "destructive",
				onPress: () => {
					const updatedTasks = tasks.filter((task) => task.id !== taskId);
					setTasks(updatedTasks);
					saveTasks(updatedTasks);
				},
			},
		]);
	};

	const renderRightActions = (taskId: string) => {
		return (
			<TouchableOpacity
				style={styles.deleteBox}
				onPress={() => handleDeleteTask(taskId)}
			>
				<Text style={styles.deleteText}>Delete</Text>
			</TouchableOpacity>
		);
	};

	const renderTask = ({ item }: { item: Task }) => (
		<Swipeable renderRightActions={() => renderRightActions(item.id)}>
			<View style={styles.taskItem}>
				<View style={styles.taskHeader}>
					<Text style={styles.taskTitle}>{item.title}</Text>
					<View style={styles.taskRatings}>
						<Text style={styles.ratingText}>P: {item.priorityRating}</Text>
						<Text style={styles.ratingText}>
							Perf: {item.performanceRating}
						</Text>
					</View>
				</View>
				{item.notes && <Text style={styles.taskNotes}>{item.notes}</Text>}
				<View style={styles.taskDetails}>
					<Text style={styles.taskDate}>
						{new Date(item.startDate).toLocaleDateString()} -{" "}
						{new Date(item.endDate).toLocaleDateString()}
					</Text>
					{item.estimatedDuration && (
						<Text style={styles.taskDuration}>
							{item.estimatedDuration} min
						</Text>
					)}
				</View>
				{item.types && item.types.length > 0 && (
					<View style={styles.taskTypes}>
						{item.types.map((type, index) => (
							<View key={index} style={styles.typeTag}>
								<Text style={styles.typeTagText}>{type}</Text>
							</View>
						))}
					</View>
				)}
				{item.subTasks && item.subTasks.length > 0 && (
					<View style={styles.subTasksContainer}>
						<Text style={styles.subTasksTitle}>
							Subtasks ({item.subTasks.length})
						</Text>
						{item.subTasks.slice(0, 2).map((subTask, index) => (
							<Text key={index} style={styles.subTaskText}>
								• {subTask.title}
							</Text>
						))}
						{item.subTasks.length > 2 && (
							<Text style={styles.moreSubTasksText}>
								+{item.subTasks.length - 2} more
							</Text>
						)}
					</View>
				)}
			</View>
		</Swipeable>
	);

	return (
		<GestureHandlerRootView style={styles.container}>
			<KeyboardAvoidingView
				behavior={Platform.OS === "ios" ? "padding" : undefined}
				style={styles.container}
			>
				<View style={styles.header}>
					<Text style={styles.headerTitle}>Tasks</Text>
					<Text style={styles.taskCount}>{tasks.length} tasks</Text>
				</View>

				<FlatList
					data={tasks}
					renderItem={renderTask}
					keyExtractor={(item) => item.id}
					contentContainerStyle={styles.taskList}
					showsVerticalScrollIndicator={false}
				/>

				{/* Floating Action Button */}
				<TouchableOpacity
					style={styles.fab}
					onPress={() => setModalVisible(true)}
				>
					<Text style={styles.fabText}>+</Text>
				</TouchableOpacity>

				{/* New Task Modal */}
				<NewTaskModal
					visible={modalVisible}
					onCancel={() => setModalVisible(false)}
					onSave={handleAddTask}
				/>
			</KeyboardAvoidingView>
		</GestureHandlerRootView>
	);
}

const styles = StyleSheet.create({
	container: {
		flex: 1,
		backgroundColor: "white",
	},
	header: {
		padding: 20,
		borderBottomWidth: 1,
		borderBottomColor: "#e0e0e0",
	},
	headerTitle: {
		fontSize: 24,
		fontWeight: "bold",
		marginBottom: 4,
	},
	taskCount: {
		fontSize: 14,
		color: "#666",
	},
	taskList: {
		padding: 16,
	},
	taskItem: {
		backgroundColor: "#f8f9fa",
		padding: 16,
		marginBottom: 12,
		borderRadius: 12,
		borderLeftWidth: 4,
		borderLeftColor: "#007AFF",
		shadowColor: "#000",
		shadowOffset: {
			width: 0,
			height: 2,
		},
		shadowOpacity: 0.1,
		shadowRadius: 3.84,
		elevation: 5,
	},
	taskHeader: {
		flexDirection: "row",
		justifyContent: "space-between",
		alignItems: "flex-start",
		marginBottom: 8,
	},
	taskTitle: {
		fontSize: 18,
		fontWeight: "600",
		flex: 1,
		marginRight: 12,
	},
	taskRatings: {
		alignItems: "flex-end",
	},
	ratingText: {
		fontSize: 12,
		color: "#666",
		marginBottom: 2,
	},
	taskNotes: {
		fontSize: 14,
		color: "#666",
		marginBottom: 8,
		fontStyle: "italic",
	},
	taskDetails: {
		flexDirection: "row",
		justifyContent: "space-between",
		alignItems: "center",
		marginBottom: 8,
	},
	taskDate: {
		fontSize: 12,
		color: "#888",
	},
	taskDuration: {
		fontSize: 12,
		color: "#007AFF",
		fontWeight: "500",
	},
	taskTypes: {
		flexDirection: "row",
		flexWrap: "wrap",
		marginBottom: 8,
	},
	typeTag: {
		backgroundColor: "#E3F2FD",
		borderRadius: 12,
		paddingHorizontal: 8,
		paddingVertical: 4,
		marginRight: 6,
		marginBottom: 4,
	},
	typeTagText: {
		color: "#1976D2",
		fontSize: 11,
		fontWeight: "500",
	},
	subTasksContainer: {
		borderTopWidth: 1,
		borderTopColor: "#e0e0e0",
		paddingTop: 8,
	},
	subTasksTitle: {
		fontSize: 12,
		fontWeight: "600",
		color: "#666",
		marginBottom: 4,
	},
	subTaskText: {
		fontSize: 12,
		color: "#666",
		marginBottom: 2,
	},
	moreSubTasksText: {
		fontSize: 11,
		color: "#999",
		fontStyle: "italic",
	},
	deleteBox: {
		backgroundColor: "#ff4444",
		justifyContent: "center",
		alignItems: "center",
		paddingHorizontal: 20,
		marginVertical: 12,
		borderRadius: 12,
		width: 80,
	},
	deleteText: {
		color: "white",
		fontWeight: "bold",
		fontSize: 14,
	},
	fab: {
		position: "absolute",
		bottom: 24,
		right: 24,
		width: 56,
		height: 56,
		borderRadius: 28,
		backgroundColor: "#007AFF",
		justifyContent: "center",
		alignItems: "center",
		shadowColor: "#000",
		shadowOffset: {
			width: 0,
			height: 4,
		},
		shadowOpacity: 0.3,
		shadowRadius: 4.65,
		elevation: 8,
	},
	fabText: {
		color: "white",
		fontSize: 24,
		fontWeight: "bold",
	},
});
