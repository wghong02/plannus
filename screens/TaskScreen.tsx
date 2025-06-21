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
} from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import {
	GestureHandlerRootView,
	Swipeable,
} from "react-native-gesture-handler";

const STORAGE_KEY = "@todos_list";

export default function TaskScreen() {
	const [todos, setTodos] = useState<string[]>([]);
	const [newTodo, setNewTodo] = useState("");

	useEffect(() => {
		(async () => {
			const json = await AsyncStorage.getItem(STORAGE_KEY);
			if (json) setTodos(JSON.parse(json));
		})();
	}, []);

	useEffect(() => {
		AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(todos));
	}, [todos]);

	const addTodo = () => {
		if (!newTodo.trim()) return;
		setTodos((prev) => [...prev, newTodo.trim()]);
		setNewTodo("");
	};

	const deleteTodo = (index: number) => {
		Alert.alert("Delete", "Are you sure?", [
			{ text: "Cancel", style: "cancel" },
			{
				text: "Delete",
				style: "destructive",
				onPress: () => {
					const copy = [...todos];
					copy.splice(index, 1);
					setTodos(copy);
				},
			},
		]);
	};

	const renderRightActions = (index: number) => (
		<View style={styles.deleteBox}>
			<Text style={styles.deleteText} onPress={() => deleteTodo(index)}>
				Delete
			</Text>
		</View>
	);

	return (
		<GestureHandlerRootView style={{ flex: 1 }}>
			<KeyboardAvoidingView
				behavior={Platform.OS === "ios" ? "padding" : undefined}
				style={styles.container}
				keyboardVerticalOffset={80}
			>
				<FlatList
					data={todos}
					keyExtractor={(item, index) => index.toString()}
					contentContainerStyle={{ padding: 16 }}
					renderItem={({ item, index }) => (
						<Swipeable renderRightActions={() => renderRightActions(index)}>
							<View style={styles.todoItem}>
								<Text>{item}</Text>
							</View>
						</Swipeable>
					)}
				/>
				<View style={styles.inputArea}>
					<TextInput
						placeholder="New todo"
						value={newTodo}
						onChangeText={setNewTodo}
						style={styles.input}
					/>
					<Button title="Add" onPress={addTodo} />
				</View>
			</KeyboardAvoidingView>
		</GestureHandlerRootView>
	);
}

const styles = StyleSheet.create({
	container: { flex: 1, backgroundColor: "white" },
	todoItem: {
		backgroundColor: "#f2f2f2",
		padding: 12,
		marginBottom: 8,
		borderRadius: 8,
	},
	inputArea: {
		padding: 16,
		borderTopColor: "#ddd",
		borderTopWidth: 1,
		backgroundColor: "white",
	},
	input: {
		borderColor: "#ccc",
		borderWidth: 1,
		padding: 10,
		borderRadius: 6,
		marginBottom: 8,
	},
	deleteBox: {
		backgroundColor: "red",
		justifyContent: "center",
		alignItems: "flex-end",
		paddingHorizontal: 20,
		marginVertical: 8,
		borderRadius: 8,
	},
	deleteText: {
		color: "white",
		fontWeight: "bold",
	},
});
