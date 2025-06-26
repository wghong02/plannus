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

interface NewTaskModalProps {
	visible: boolean;
	onCancel: () => void;
	onSave: (title: string, time: string, notes: string) => void;
	initialTitle?: string;
	initialTime?: string;
	initialNotes?: string;

	titleLabel?: string;
}

const generateTimeOptions = () => {
	const times = [];
	for (let hour = 0; hour < 24; hour++) {
		for (let minute = 0; minute < 60; minute += 30) {
			const timeString = `${hour.toString().padStart(2, "0")}:${minute
				.toString()
				.padStart(2, "0")}`;
			times.push(timeString);
		}
	}
	return times;
};

const formatTime = (time: string) => {
	const [hours, minutes] = time.split(":");
	const hour = parseInt(hours);
	const ampm = hour >= 12 ? "PM" : "AM";
	const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
	return `${displayHour}:${minutes} ${ampm}`;
};

export default function NewTaskModal({
	visible,
	onCancel,
	onSave,
	initialTitle = "",
	initialTime = "09:00",
	initialNotes = "",
	titleLabel = "Task Description",
}: NewTaskModalProps) {
	const [title, setTitle] = useState(initialTitle);
	const [selectedTime, setSelectedTime] = useState(initialTime);
	const [notes, setNotes] = useState(initialNotes);
	const [showTimeDropdown, setShowTimeDropdown] = useState(false);

	React.useEffect(() => {
		setTitle(initialTitle);
		setSelectedTime(initialTime);
		setNotes(initialNotes);
	}, [visible, initialTitle, initialTime, initialNotes]);

	return (
		<Modal visible={visible} transparent animationType="slide">
			<View style={styles.overlay}>
				<View style={styles.bottomSheet}>
					<View style={styles.header}>
						<TouchableOpacity onPress={onCancel} style={styles.headerButton}>
							<Text style={styles.cancelText}>Cancel</Text>
						</TouchableOpacity>
						<Text style={styles.headerTitle}>New Task</Text>
						<TouchableOpacity
							onPress={() => onSave(title, selectedTime, notes)}
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
							<Text style={styles.sectionLabel}>{titleLabel}</Text>
							<TextInput
								style={styles.input}
								placeholder={titleLabel}
								value={title}
								onChangeText={setTitle}
							/>

							{/* Section 2: Time Picker */}
							<Text style={styles.sectionLabel}>Time</Text>
							<TouchableOpacity
								style={styles.timeRow}
								onPress={() => setShowTimeDropdown((v) => !v)}
							>
								<Text style={styles.timeRowText}>
									{formatTime(selectedTime)}
								</Text>
								<Text style={styles.timeRowIcon}>▼</Text>
							</TouchableOpacity>
							{showTimeDropdown && (
								<View style={styles.dropdown}>
									<FlatList
										data={generateTimeOptions()}
										keyExtractor={(item) => item}
										renderItem={({ item }) => (
											<TouchableOpacity
												style={[
													styles.dropdownItem,
													selectedTime === item && styles.selectedDropdownItem,
												]}
												onPress={() => {
													setSelectedTime(item);
													setShowTimeDropdown(false);
												}}
											>
												<Text style={styles.dropdownItemText}>
													{formatTime(item)}
												</Text>
											</TouchableOpacity>
										)}
										style={styles.dropdownList}
									/>
								</View>
							)}

							{/* Section 3: Notes */}
							<Text style={styles.sectionLabel}>Notes</Text>
							<TextInput
								style={styles.notesInput}
								placeholder="Add notes..."
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
	dropdown: {
		position: "absolute",
		left: 0,
		right: 0,
		top: 110,
		backgroundColor: "white",
		borderRadius: 6,
		borderWidth: 1,
		borderColor: "#ccc",
		zIndex: 10,
		maxHeight: 200,
	},
	dropdownList: {
		maxHeight: 200,
	},
	dropdownItem: {
		padding: 12,
	},
	selectedDropdownItem: {
		backgroundColor: "#e0e0e0",
	},
	dropdownItemText: {
		fontSize: 16,
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
});
