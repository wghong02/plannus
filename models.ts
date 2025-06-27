export interface Event {
	id: string;
	title: string;
	allDay?: boolean;
	startTime?: string;
	endTime?: string;
	notes?: string;
}

export type EventMap = Record<string, Event[]>;

export interface TaskBase extends Event {
	priorityRating: number;
	performanceRating: number;
	completed: boolean;
	completedAt?: string;
}

export type FrequencyPattern =
	| "daily"
	| "weekly"
	| "monthly"
	| "yearly"
	| "custom"
	| "none";

export interface Task extends TaskBase {
	startDate: string;
	endDate: string;
	frequencyPattern: FrequencyPattern;
	frequencyCount: number;
	subTasks: SubTask[];
	types?: string[];
	estimatedDuration?: number;
	actualDuration?: number;
	recurring: boolean;
}

export interface SubTask extends TaskBase {
	date: string;
	parentTaskId: string;
	order: number;
}
