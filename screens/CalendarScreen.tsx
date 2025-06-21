import React, { useEffect, useState } from "react";
import {
	View,
	TextInput,
	Button,
	Text,
	Platform,
	TouchableOpacity,
	Alert,
	FlatList,
} from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { Calendar } from "react-native-calendars";
import { SafeAreaView } from "react-native-safe-area-context";
import { StyleSheet } from "react-native";

const STORAGE_KEY = "agenda";

export default function CalendarScreen() {
	const [selectedDate, setSelectedDate] = useState("");
	const [agenda, setAgenda] = useState<Record<string, string[]>>({});
	const [inputValue, setInputValue] = useState("");
	const [editIndex, setEditIndex] = useState<number | null>(null);

	// Load from AsyncStorage
	useEffect(() => {
		(async () => {
			const json = await AsyncStorage.getItem(STORAGE_KEY);
			if (json) {
				setAgenda(JSON.parse(json));
			}
		})();
	}, []);

	// Save to AsyncStorage
	useEffect(() => {
		AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(agenda));
	}, [agenda]);

	const handleSubmit = () => {
		if (!inputValue) return;
		const items = agenda[selectedDate] || [];

		let updatedItems: string[];
		if (editIndex !== null) {
			// Edit
			updatedItems = [...items];
			updatedItems[editIndex] = inputValue;
		} else {
			// Add new
			updatedItems = [...items, inputValue];
		}

		setAgenda({ ...agenda, [selectedDate]: updatedItems });
		setInputValue("");
		setEditIndex(null);
	};

	const handleDelete = (index: number) => {
		Alert.alert("Delete Item", "Are you sure?", [
			{ text: "Cancel", style: "cancel" },
			{
				text: "Delete",
				style: "destructive",
				onPress: () => {
					const updatedItems = [...(agenda[selectedDate] || [])];
					updatedItems.splice(index, 1);
					setAgenda({ ...agenda, [selectedDate]: updatedItems });
					if (editIndex === index) {
						setInputValue("");
						setEditIndex(null);
					}
				},
			},
		]);
	};

	const handleEdit = (index: number) => {
		const item = agenda[selectedDate][index];
		setInputValue(item);
		setEditIndex(index);
	};

	const agendaItems = agenda[selectedDate] || [];

	return (
		<>
			<Calendar
				onDayPress={(day) => setSelectedDate(day.dateString)}
				markedDates={{
					[selectedDate]: { selected: true, selectedColor: "blue" },
				}}
			/>

			{selectedDate ? (
				<View style={styles.agendaContainer}>
					<Text style={styles.agendaTitle}>Agenda for {selectedDate}</Text>

					<FlatList
						data={agendaItems}
						keyExtractor={(item, index) => index.toString()}
						ListEmptyComponent={
							<Text style={styles.noItems}>No events yet</Text>
						}
						renderItem={({ item, index }) => (
							<View style={styles.agendaItem}>
								<TouchableOpacity
									style={styles.itemTextContainer}
									onPress={() => handleEdit(index)}
								>
									<Text>{item}</Text>
								</TouchableOpacity>
								<TouchableOpacity onPress={() => handleDelete(index)}>
									<Text style={styles.deleteButton}>✕</Text>
								</TouchableOpacity>
							</View>
						)}
					/>

					<TextInput
						style={styles.input}
						placeholder="New or edited item"
						value={inputValue}
						onChangeText={setInputValue}
					/>
					<Button
						title={editIndex !== null ? "Save Edit" : "Add Item"}
						onPress={handleSubmit}
					/>
				</View>
			) : (
				<Text style={styles.selectPrompt}>Select a date to view agenda</Text>
			)}
		</>
	);
}

const styles = StyleSheet.create({
	container: { flex: 1, backgroundColor: "white" },
	agendaContainer: { flex: 1, padding: 16 },
	agendaTitle: { fontSize: 16, fontWeight: "bold", marginBottom: 8 },
	agendaItem: {
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
	input: {
		borderColor: "#ccc",
		borderWidth: 1,
		padding: 8,
		marginTop: 12,
		marginBottom: 8,
		borderRadius: 6,
	},
	selectPrompt: {
		textAlign: "center",
		marginTop: 40,
		color: "#888",
		fontSize: 16,
	},
});
