import AsyncStorage from "@react-native-async-storage/async-storage";
import type { TaskMap } from "../models";

const STORAGE_KEY = "task";

export async function loadTasks(): Promise<TaskMap> {
	console.log("loading tasks for storage");
	const json = await AsyncStorage.getItem(STORAGE_KEY);
	return json ? JSON.parse(json) : {};
}

export async function saveTasks(tasks: TaskMap): Promise<void> {
	console.log("saving tasks to storage", tasks);
	await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

export async function deleteTask(
	tasks: TaskMap,
	date: string,
	index: number
): Promise<TaskMap> {
	console.log("deleting task from storage", tasks, date, index);

	if (!tasks[date]) return tasks;
	const updatedItems = [...tasks[date]];
	updatedItems.splice(index, 1);

	// If no tasks left, delete the date
	if (updatedItems.length === 0) {
		const { [date]: deleted, ...remainingTasks } = tasks;
		await saveTasks(remainingTasks);
		return remainingTasks;
	}

	const updatedTasks = { ...tasks, [date]: updatedItems };
	await saveTasks(updatedTasks);
	return updatedTasks;
}
