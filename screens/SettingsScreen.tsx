import React, { useEffect, useState } from "react";
import {
	View,
	TextInput,
	Button,
	Text,
	TouchableOpacity,
	Alert,
	FlatList,
} from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { Calendar } from "react-native-calendars";
import { StyleSheet } from "react-native";

const STORAGE_KEY = "settings";

export default function SettingsScreen() {
	return <></>;
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
