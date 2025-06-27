import React, { useState } from "react";
import {
	View,
	Text,
	TouchableOpacity,
	StyleSheet,
	ScrollView,
} from "react-native";

interface DatePickerWheelProps {
	date: string; // Format: YYYY-MM-DD
	onDateChange: (date: string) => void;
}

const generateYears = () => {
	const currentYear = new Date().getFullYear();
	const years = [];
	for (let year = currentYear - 10; year <= currentYear + 10; year++) {
		years.push(year.toString());
	}
	return years;
};

const generateMonths = () => {
	const months = [];
	for (let month = 1; month <= 12; month++) {
		months.push(month.toString().padStart(2, "0"));
	}
	return months;
};

const generateDays = (year: string, month: string) => {
	const yearNum = parseInt(year);
	const monthNum = parseInt(month);
	const daysInMonth = new Date(yearNum, monthNum, 0).getDate();
	const days = [];
	for (let day = 1; day <= daysInMonth; day++) {
		days.push(day.toString().padStart(2, "0"));
	}
	return days;
};

const getMonthName = (month: string) => {
	const monthNames = [
		"Jan",
		"Feb",
		"Mar",
		"Apr",
		"May",
		"Jun",
		"Jul",
		"Aug",
		"Sep",
		"Oct",
		"Nov",
		"Dec",
	];
	return monthNames[parseInt(month) - 1];
};

// Parse date into components
const parseDate = (date: string) => {
	if (!date) {
		const today = new Date();
		return {
			year: today.getFullYear().toString(),
			month: (today.getMonth() + 1).toString().padStart(2, "0"),
			day: today.getDate().toString().padStart(2, "0"),
		};
	}
	const [year, month, day] = date.split("-");
	return { year, month, day };
};

// Combine date components back to YYYY-MM-DD format
const combineDate = (year: string, month: string, day: string) => {
	return `${year}-${month}-${day}`;
};

export default function DatePickerWheel({
	date,
	onDateChange,
}: DatePickerWheelProps) {
	const { year, month, day } = parseDate(date);
	const [selectedYear, setSelectedYear] = useState(year);
	const [selectedMonth, setSelectedMonth] = useState(month);
	const [selectedDay, setSelectedDay] = useState(day);

	const handleYearChange = (newYear: string) => {
		setSelectedYear(newYear);
		const newDate = combineDate(newYear, selectedMonth, selectedDay);
		onDateChange(newDate);
	};

	const handleMonthChange = (newMonth: string) => {
		setSelectedMonth(newMonth);
		// Adjust day if it exceeds the new month's days
		const daysInNewMonth = new Date(
			parseInt(selectedYear),
			parseInt(newMonth),
			0
		).getDate();
		const adjustedDay =
			parseInt(selectedDay) > daysInNewMonth
				? daysInNewMonth.toString().padStart(2, "0")
				: selectedDay;
		setSelectedDay(adjustedDay);
		const newDate = combineDate(selectedYear, newMonth, adjustedDay);
		onDateChange(newDate);
	};

	const handleDayChange = (newDay: string) => {
		setSelectedDay(newDay);
		const newDate = combineDate(selectedYear, selectedMonth, newDay);
		onDateChange(newDate);
	};

	return (
		<View style={styles.datePickerContainer}>
			<View style={styles.datePickerWheel}>
				<View style={styles.wheelColumn}>
					<Text style={styles.wheelLabel}>Year</Text>
					<ScrollView style={styles.wheel} showsVerticalScrollIndicator={false}>
						{generateYears().map((y) => (
							<TouchableOpacity
								key={y}
								style={[
									styles.wheelItem,
									selectedYear === y && styles.selectedWheelItem,
								]}
								onPress={() => handleYearChange(y)}
							>
								<Text
									style={[
										styles.wheelItemText,
										selectedYear === y && styles.selectedWheelItemText,
									]}
								>
									{y}
								</Text>
							</TouchableOpacity>
						))}
					</ScrollView>
				</View>
				<View style={styles.wheelColumn}>
					<Text style={styles.wheelLabel}>Month</Text>
					<ScrollView style={styles.wheel} showsVerticalScrollIndicator={false}>
						{generateMonths().map((m) => (
							<TouchableOpacity
								key={m}
								style={[
									styles.wheelItem,
									selectedMonth === m && styles.selectedWheelItem,
								]}
								onPress={() => handleMonthChange(m)}
							>
								<Text
									style={[
										styles.wheelItemText,
										selectedMonth === m && styles.selectedWheelItemText,
									]}
								>
									{getMonthName(m)}
								</Text>
							</TouchableOpacity>
						))}
					</ScrollView>
				</View>
				<View style={styles.wheelColumn}>
					<Text style={styles.wheelLabel}>Day</Text>
					<ScrollView style={styles.wheel} showsVerticalScrollIndicator={false}>
						{generateDays(selectedYear, selectedMonth).map((d) => (
							<TouchableOpacity
								key={d}
								style={[
									styles.wheelItem,
									selectedDay === d && styles.selectedWheelItem,
								]}
								onPress={() => handleDayChange(d)}
							>
								<Text
									style={[
										styles.wheelItemText,
										selectedDay === d && styles.selectedWheelItemText,
									]}
								>
									{d}
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
	datePickerContainer: {
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
	datePickerWheel: {
		flexDirection: "row",
		justifyContent: "space-between",
		paddingHorizontal: 16,
		paddingVertical: 8,
	},
	wheelColumn: {
		flex: 1,
		alignItems: "center",
	},
	wheelLabel: {
		fontSize: 12,
		color: "#666",
		marginBottom: 4,
		fontWeight: "500",
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
