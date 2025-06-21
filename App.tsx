import "react-native-gesture-handler";
import React from "react";
import { NavigationContainer } from "@react-navigation/native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import TabNavigator from "./components/TabNavigator";

export default function App() {
	return (
		<SafeAreaProvider>
			<NavigationContainer>
				<TabNavigator />
			</NavigationContainer>
		</SafeAreaProvider>
	);
}
