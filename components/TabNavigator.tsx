import React from "react";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { Ionicons } from "@expo/vector-icons";
import CalendarScreen from "../screens/CalendarScreen";
import TaskScreen from "../screens/TaskScreen";
import PerformanceScreen from "../screens/PerformanceScreen";
import SettingsScreen from "../screens/SettingsScreen";

const Tab = createBottomTabNavigator();

export default function TabNavigator() {
	return (
		<Tab.Navigator
			screenOptions={({ route }) => ({
				tabBarIcon: ({ focused, color, size }) => {
					let iconName: keyof typeof Ionicons.glyphMap;

					if (route.name === "Calendar") {
						iconName = focused ? "calendar" : "calendar-outline";
					} else if (route.name === "Tasks") {
						iconName = focused ? "list" : "list-outline";
					} else if (route.name === "Performance") {
						iconName = focused ? "bar-chart" : "bar-chart-outline";
					} else if (route.name === "Settings") {
						iconName = focused ? "settings" : "settings-outline";
					} else {
						iconName = "help-outline";
					}

					return <Ionicons name={iconName} size={size} color={color} />;
				},
				tabBarActiveTintColor: "#007AFF",
				tabBarInactiveTintColor: "gray",
			})}
		>
			<Tab.Screen name="Calendar" component={CalendarScreen} />
			<Tab.Screen name="Tasks" component={TaskScreen} />
			<Tab.Screen name="Performance" component={PerformanceScreen} />
			<Tab.Screen name="Settings" component={SettingsScreen} />
		</Tab.Navigator>
	);
}
