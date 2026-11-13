import { SPATIAL_CELL_SIZE } from './constants';

export interface SpatialEntity {
  id: number;
  x: number;
  y: number;
  radius: number;
}

export class SpatialHash<T extends SpatialEntity> {
  private cellSize: number;
  private grid: Map<string, T[]> = new Map();

  constructor(cellSize: number = SPATIAL_CELL_SIZE) {
    this.cellSize = cellSize;
  }

  private hash(cx: number, cy: number): string {
    return `${cx}:${cy}`;
  }

  clear(): void {
    this.grid.clear();
  }

  insert(entity: T): void {
    const minCx = Math.floor((entity.x - entity.radius) / this.cellSize);
    const maxCx = Math.floor((entity.x + entity.radius) / this.cellSize);
    const minCy = Math.floor((entity.y - entity.radius) / this.cellSize);
    const maxCy = Math.floor((entity.y + entity.radius) / this.cellSize);

    for (let cx = minCx; cx <= maxCx; cx++) {
      for (let cy = minCy; cy <= maxCy; cy++) {
        const key = this.hash(cx, cy);
        let list = this.grid.get(key);
        if (!list) {
          list = [];
          this.grid.set(key, list);
        }
        list.push(entity);
      }
    }
  }

  query(x: number, y: number, radius: number): T[] {
    const minCx = Math.floor((x - radius) / this.cellSize);
    const maxCx = Math.floor((x + radius) / this.cellSize);
    const minCy = Math.floor((y - radius) / this.cellSize);
    const maxCy = Math.floor((y + radius) / this.cellSize);

    const foundSet = new Set<number>();
    const results: T[] = [];

    for (let cx = minCx; cx <= maxCx; cx++) {
      for (let cy = minCy; cy <= maxCy; cy++) {
        const key = this.hash(cx, cy);
        const list = this.grid.get(key);
        if (!list) continue;

        for (const item of list) {
          if (!foundSet.has(item.id)) {
            foundSet.add(item.id);
            // Circle-circle distance check
            const distSq = (item.x - x) ** 2 + (item.y - y) ** 2;
            const combinedR = item.radius + radius;
            if (distSq <= combinedR * combinedR) {
              results.push(item);
            }
          }
        }
      }
    }

    return results;
  }
}
