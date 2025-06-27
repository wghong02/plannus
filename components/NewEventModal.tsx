import React, { useState } from "react";
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
} from "react-native";
import { formatTime } from "../utils/functions";
import TimePickerWheel from "./TimePickerWheel";

interface NewEventModalProps {
	visible: boolean;
	onCancel: () => void;
	onSave: (
		title: string,
		startTime: string,
		endTime: string,
		notes: string,
		allDay: boolean
	) => void;
	initialTitle?: string;
	initialStartTime?: string;
	initialEndTime?: string;
	initialNotes?: string;
	initialAllDay?: boolean;

	titleLabel?: string;
}

export default function NewEventModal({
	visible,
	onCancel,
	onSave,
	initialTitle = "New Event",
	initialStartTime = "08:00",
	initialEndTime = "09:00",
	initialNotes = "",
	initialAllDay = false,
}: NewEventModalProps) {
	const [title, setTitle] = useState(initialTitle);
	const [startTime, setStartTime] = useState(initialStartTime);
	const [endTime, setEndTime] = useState(initialEndTime);
	const [notes, setNotes] = useState(initialNotes);
	const [allDay, setAllDay] = useState(initialAllDay);
	const [showStartTimePicker, setShowStartTimePicker] = useState(false);
	const [showEndTimePicker, setShowEndTimePicker] = useState(false);

	React.useEffect(() => {
		if (visible) {
			setTitle(initialTitle);
			setStartTime(initialStartTime);
			setEndTime(initialEndTime);
			setNotes(initialNotes);
			setAllDay(initialAllDay);
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

	const handleAllDayToggle = () => {
		setAllDay(!allDay);
		if (!allDay) {
			// If turning on allDay, clear times
			setStartTime("");
			setEndTime("");
		} else {
			// If turning off allDay, set default times
			setStartTime("08:00");
			setEndTime("09:00");
		}
		setShowStartTimePicker(false);
		setShowEndTimePicker(false);
	};

	return (
		<Modal visible={visible} transparent animationType="slide">
			<View style={styles.overlay}>
				<View style={styles.bottomSheet}>
					<View style={styles.header}>
						<TouchableOpacity onPress={onCancel} style={styles.headerButton}>
							<Text style={styles.cancelText}>Cancel</Text>
						</TouchableOpacity>
						<Text style={styles.headerTitle}>New Event</Text>
						<TouchableOpacity
							onPress={() => onSave(title, startTime, endTime, notes, allDay)}
							style={styles.headerButton}
						>
							<Text style={styles.saveText}>Save</Text>
						</TouchableOpacity>
					</View>

					<KeyboardAvoidingView
						behavior={Platform.OS === "ios" ? "padding" : undefined}
						style={{ flex: 1 }}
					>
						<ScrollView contentContainerStyle={styles.content}>
							{/* Section 1: Description */}
							<Text style={styles.sectionLabel}>Event Description</Text>
							<TextInput
								style={styles.input}
								placeholder="Description"
								placeholderTextColor="#999"
								value={title}
								onChangeText={setTitle}
							/>

							{/* Section 2: Time Pickers */}
							{/* If all day */}
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
									{/* Start Time */}
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

									{/* End Time */}
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

							{/* Section 3: Notes */}
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
});
