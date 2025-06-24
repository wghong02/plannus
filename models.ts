export interface Task {
	id: string;
	title: string;
	time: string;
	notes?: string;
}

export type TaskMap = Record<string, Task[]>;
