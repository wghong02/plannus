import AsyncStorage from "@react-native-async-storage/async-storage";
import type { EventMap } from "../models";

const STORAGE_KEY = "event";

export async function loadEvents(): Promise<EventMap> {
	console.log("loading events for storage");
	const json = await AsyncStorage.getItem(STORAGE_KEY);
	return json ? JSON.parse(json) : {};
}

export async function saveEvents(events: EventMap): Promise<void> {
	console.log("saving events to storage", events);
	await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(events));
}

export async function deleteEvent(
	events: EventMap,
	date: string,
	index: number
): Promise<EventMap> {
	console.log("deleting event from storage", events, date, index);

	if (!events[date]) return events;
	const updatedItems = [...events[date]];
	updatedItems.splice(index, 1);

	// If no events left, delete the date
	if (updatedItems.length === 0) {
		const { [date]: deleted, ...remainingEvents } = events;
		await saveEvents(remainingEvents);
		return remainingEvents;
	}

	const updatedEvents = { ...events, [date]: updatedItems };
	await saveEvents(updatedEvents);
	return updatedEvents;
}
