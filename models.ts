export interface Event {
	id: string;
	title: string;
	allDay?: boolean;
	startTime?: string;
	endTime?: string;
	notes?: string;
}

export type EventMap = Record<string, Event[]>;
