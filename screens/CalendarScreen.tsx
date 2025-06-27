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
import NewEventModal from "../components/NewEventModal";
import { loadEvents, saveEvents, deleteEvent } from "../utils/apis";
import type { Event, EventMap } from "../models";

const STORAGE_KEY = "event";

export default function CalendarScreen() {
	const [selectedDate, setSelectedDate] = useState("");
	const [event, setEvent] = useState<EventMap>({});
	const [editIndex, setEditIndex] = useState<number | null>(null);
	const [showEventModal, setShowEventModal] = useState(false);
	const [modalInitialTitle, setModalInitialTitle] = useState("");
	const [modalInitialStartTime, setModalInitialStartTime] = useState("");
	const [modalInitialEndTime, setModalInitialEndTime] = useState("");
	const [modalInitialNotes, setModalInitialNotes] = useState("");
	const [modalInitialAllDay, setModalInitialAllDay] = useState(false);

	// Load from AsyncStorage
	useEffect(() => {
		(async () => {
			const loaded = await loadEvents(STORAGE_KEY);
			setEvent(loaded);
		})();
	}, []);

	// Reset modal state when modal closes
	useEffect(() => {
		if (!showEventModal) {
			setModalInitialTitle("New Event");
			setModalInitialStartTime("08:00");
			setModalInitialEndTime("09:00");
			setModalInitialNotes("");
			setModalInitialAllDay(false);
		}
	}, [showEventModal]);

	const handleAddEvent = () => {
		setEditIndex(null);
		setShowEventModal(true);
	};

	const handleEdit = (index: number) => {
		const item = event[selectedDate][index];
		setEditIndex(index);
		setModalInitialTitle(item.title);
		setModalInitialStartTime(item.startTime || "");
		setModalInitialEndTime(item.endTime || "");
		setModalInitialNotes(item.notes || "");
		setModalInitialAllDay(item.allDay || false);
		setShowEventModal(true);
	};

	const handleSaveEvent = async (
		title: string,
		startTime: string,
		endTime: string,
		notes: string,
		allDay: boolean
	) => {
		if (!title) {
			setShowEventModal(false);
			return;
		}
		const items = event[selectedDate] || [];
		let updatedItems: Event[];
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
			const newEvent: Event = {
				id: Date.now().toString(),
				title,
				allDay,
				startTime,
				endTime,
				notes,
			};
			updatedItems = [...items, newEvent];
		}
		// Sort by start time if available, otherwise by title
		updatedItems.sort((a, b) => {
			if (a.startTime && b.startTime) {
				return a.startTime.localeCompare(b.startTime);
			}
			return a.title.localeCompare(b.title);
		});
		const updatedEvent = { ...event, [selectedDate]: updatedItems };

		try {
			await saveEvents(updatedEvent, STORAGE_KEY);
			setEvent(updatedEvent);
			setShowEventModal(false);
			setEditIndex(null);
		} catch (error) {
			console.error("Failed to save event:", error);
			// You might want to show an alert here to inform the user
		}
	};

	const handleDelete = (index: number) => {
		Alert.alert("Delete Event", "Are you sure?", [
			{ text: "Cancel", style: "cancel" },
			{
				text: "Delete",
				style: "destructive",
				onPress: async () => {
					const updated = await deleteEvent(
						event,
						selectedDate,
						index,
						STORAGE_KEY
					);
					setEvent(updated);
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

	const eventItems = event[selectedDate] || [];

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
						<View style={styles.eventContainer}>
							<Text style={styles.eventTitle}>Events for {selectedDate}</Text>

							<FlatList
								data={eventItems}
								keyExtractor={(item) => item.id}
								ListEmptyComponent={
									<Text style={styles.noItems}>No events yet</Text>
								}
								renderItem={({ item, index }) => (
									<View style={styles.eventItem}>
										<TouchableOpacity
											style={styles.itemTextContainer}
											onPress={() => handleEdit(index)}
										>
											<Text style={styles.eventItemTitle}>{item.title}</Text>
										</TouchableOpacity>
										<View style={styles.eventTimeContainer}>
											{item.startTime && (
												<Text style={styles.eventTime}>
													{formatTime(item.startTime)}
												</Text>
											)}
											{item.endTime && (
												<Text style={styles.eventEndTime}>
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
								onPress={handleAddEvent}
							>
								<Text style={styles.addButtonText}>+ Add Event</Text>
							</TouchableOpacity>
						</View>
					) : (
						<Text style={styles.selectPrompt}>
							Select a date to view events
						</Text>
					)}
				</KeyboardAvoidingView>
			</TouchableWithoutFeedback>

			<NewEventModal
				visible={showEventModal}
				onCancel={() => setShowEventModal(false)}
				onSave={handleSaveEvent}
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
	eventContainer: { flex: 1, padding: 16 },
	eventTitle: { fontSize: 16, fontWeight: "bold", marginBottom: 8 },
	eventItem: {
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
	eventTimeContainer: {
		width: 80,
		padding: 8,
		backgroundColor: "#f3f4f6",
		borderRadius: 6,
	},
	eventTime: {
		fontSize: 14,
		fontWeight: "bold",
	},
	eventItemTitle: {
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
	eventEndTime: {
		fontSize: 12,
		color: "#888",
	},
});
