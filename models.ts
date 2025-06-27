export interface Task {
	id: string;
	title: string;
	allDay?: boolean;
	startTime?: string;
	endTime?: string;
	notes?: string;
}

export type TaskMap = Record<string, Task[]>;
