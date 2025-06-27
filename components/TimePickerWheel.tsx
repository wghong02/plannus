import React, { useState } from "react";
import {
	View,
	Text,
	TouchableOpacity,
	StyleSheet,
	ScrollView,
} from "react-native";

interface TimePickerWheelProps {
	time: string;
	onTimeChange: (time: string) => void;
}

const generateHours = () => {
	const hours = [];
	for (let hour = 0; hour < 24; hour++) {
		hours.push(hour.toString().padStart(2, "0"));
	}
	return hours;
};

const generateMinutes = () => {
	const minutes = [];
	for (let minute = 0; minute < 60; minute += 5) {
		minutes.push(minute.toString().padStart(2, "0"));
	}
	return minutes;
};

const generateAMPM = () => ["AM", "PM"];

// Parse time into components
const parseTime = (time: string) => {
	if (!time) return { hour: "09", minute: "00", ampm: "AM" };
	const [hours, minutes] = time.split(":");
	const hour = parseInt(hours);
	const ampm = hour >= 12 ? "PM" : "AM";
	const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
	return {
		hour: displayHour.toString().padStart(2, "0"),
		minute: minutes,
		ampm,
	};
};

// Combine time components back to HH:MM format
const combineTime = (hour: string, minute: string, ampm: string) => {
	let hour24 = parseInt(hour);
	if (ampm === "PM" && hour24 !== 12) hour24 += 12;
	if (ampm === "AM" && hour24 === 12) hour24 = 0;
	return `${hour24.toString().padStart(2, "0")}:${minute}`;
};

export default function TimePickerWheel({
	time,
	onTimeChange,
}: TimePickerWheelProps) {
	const { hour, minute, ampm } = parseTime(time);
	const [selectedHour, setSelectedHour] = useState(hour);
	const [selectedMinute, setSelectedMinute] = useState(minute);
	const [selectedAMPM, setSelectedAMPM] = useState(ampm);

	const handleHourChange = (newHour: string) => {
		setSelectedHour(newHour);
		const newTime = combineTime(newHour, selectedMinute, selectedAMPM);
		onTimeChange(newTime);
	};

	const handleMinuteChange = (newMinute: string) => {
		setSelectedMinute(newMinute);
		const newTime = combineTime(selectedHour, newMinute, selectedAMPM);
		onTimeChange(newTime);
	};

	const handleAMPMChange = (newAMPM: string) => {
		setSelectedAMPM(newAMPM);
		const newTime = combineTime(selectedHour, selectedMinute, newAMPM);
		onTimeChange(newTime);
	};

	return (
		<View style={styles.timePickerContainer}>
			<View style={styles.timePickerWheel}>
				<View style={styles.wheelColumn}>
					<ScrollView style={styles.wheel} showsVerticalScrollIndicator={false}>
						{generateHours().map((h) => (
							<TouchableOpacity
								key={h}
								style={[
									styles.wheelItem,
									selectedHour === h && styles.selectedWheelItem,
								]}
								onPress={() => handleHourChange(h)}
							>
								<Text
									style={[
										styles.wheelItemText,
										selectedHour === h && styles.selectedWheelItemText,
									]}
								>
									{h}
								</Text>
							</TouchableOpacity>
						))}
					</ScrollView>
				</View>
				<View style={styles.wheelColumn}>
					<ScrollView style={styles.wheel} showsVerticalScrollIndicator={false}>
						{generateMinutes().map((m) => (
							<TouchableOpacity
								key={m}
								style={[
									styles.wheelItem,
									selectedMinute === m && styles.selectedWheelItem,
								]}
								onPress={() => handleMinuteChange(m)}
							>
								<Text
									style={[
										styles.wheelItemText,
										selectedMinute === m && styles.selectedWheelItemText,
									]}
								>
									{m}
								</Text>
							</TouchableOpacity>
						))}
					</ScrollView>
				</View>
				<View style={styles.wheelColumn}>
					<ScrollView style={styles.wheel} showsVerticalScrollIndicator={false}>
						{generateAMPM().map((ap) => (
							<TouchableOpacity
								key={ap}
								style={[
									styles.wheelItem,
									selectedAMPM === ap && styles.selectedWheelItem,
								]}
								onPress={() => handleAMPMChange(ap)}
							>
								<Text
									style={[
										styles.wheelItemText,
										selectedAMPM === ap && styles.selectedWheelItemText,
									]}
								>
									{ap}
								</Text>
							</TouchableOpacity>
						))}
					</ScrollView>
				</View>
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	timePickerContainer: {
		backgroundColor: "white",
		borderRadius: 8,
		borderWidth: 1,
		borderColor: "#ccc",
		marginTop: 4,
		shadowColor: "#000",
		shadowOffset: {
			width: 0,
			height: 2,
		},
		shadowOpacity: 0.1,
		shadowRadius: 3.84,
		elevation: 5,
	},
	timePickerWheel: {
		flexDirection: "row",
		justifyContent: "space-between",
		paddingHorizontal: 16,
		paddingVertical: 8,
	},
	wheelColumn: {
		flex: 1,
		alignItems: "center",
	},
	wheel: {
		height: 120,
	},
	wheelItem: {
		height: 40,
		justifyContent: "center",
		alignItems: "center",
		paddingHorizontal: 8,
	},
	selectedWheelItem: {
		backgroundColor: "#e0e0e0",
		borderRadius: 8,
	},
	wheelItemText: {
		fontSize: 16,
	},
	selectedWheelItemText: {
		fontWeight: "bold",
		color: "#007AFF",
	},
});
