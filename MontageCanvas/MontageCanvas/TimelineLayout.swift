//
//  TimelineLayout.swift
//  Montage
//
//  Created by Germán Leiva on 29/03/2018.
//  Copyright © 2018 ExSitu. All rights reserved.
//

import UIKit

let DaysPerWeek:CGFloat = 7
let HoursPerDay:CGFloat = 24
let HorizontalSpacing:CGFloat = 10
let HeightPerHour:CGFloat = 50
let DayHeaderHeight:CGFloat = 40
let HourHeaderWidth:CGFloat = 100

class TimelineLayout: UICollectionViewFlowLayout {
    override var collectionViewContentSize: CGSize {
        // Don't scroll horizontally
        let contentWidth = collectionView!.bounds.size.width
        
        // Scroll vertically to display a full day
        let contentHeight = DayHeaderHeight + (HeightPerHour * HoursPerDay)
        
        let contentSize = CGSize(width: contentWidth, height:contentHeight)
        return contentSize
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var layoutAttributes = [UICollectionViewLayoutAttributes]()
        
        // Cells
        // We call a custom helper method -indexPathsOfItemsInRect: here
        // which computes the index paths of the cells that should be included
        // in rect.
        
        let visibleIndexPaths = indexPathsOfItems(inRect: rect)
        
        for indexPath in visibleIndexPaths {
            if let attributes = layoutAttributesForItem(at: indexPath) {
                layoutAttributes.append(attributes)
            }
        }
            
            // Supplementary views
//            NSArray *dayHeaderViewIndexPaths =
//                [self indexPathsOfDayHeaderViewsInRect:rect];
//            for (NSIndexPath *indexPath in dayHeaderViewIndexPaths) {
//                UICollectionViewLayoutAttributes *attributes =
//                    [self layoutAttributesForSupplementaryViewOfKind:@"DayHeaderView"
//                        atIndexPath:indexPath];
//                [layoutAttributes addObject:attributes];
//            }
//            NSArray *hourHeaderViewIndexPaths =
//                [self indexPathsOfHourHeaderViewsInRect:rect];
//            for (NSIndexPath *indexPath in hourHeaderViewIndexPaths) {
//                UICollectionViewLayoutAttributes *attributes =
//                    [self layoutAttributesForSupplementaryViewOfKind:@"HourHeaderView"
//                        atIndexPath:indexPath];
//                [layoutAttributes addObject:attributes];
//            }
        
        return layoutAttributes
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let dataSource = collectionView!.dataSource as? TierCollectionDataSource else {
            return nil
        }

        let event = dataSource.eventAt(indexPath:indexPath)

        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frameForEvent(event: event)

        return attributes
    }
    
    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: elementKind, with: indexPath)
        
        let totalWidth = collectionViewContentSize.width
        if elementKind.isEqual("DayHeaderView") {
            let availableWidth = totalWidth - HourHeaderWidth
            let widthPerDay = availableWidth / DaysPerWeek
            attributes.frame = CGRect(x:HourHeaderWidth + (widthPerDay * CGFloat(indexPath.item)), y:0, width:widthPerDay, height:DayHeaderHeight)
            attributes.zIndex = -10
        } else if elementKind.isEqual("HourHeaderView") {
            attributes.frame = CGRect(x:0, y:DayHeaderHeight + HeightPerHour * CGFloat(indexPath.item), width: totalWidth, height: HeightPerHour)
            attributes.zIndex = -10
        }
        return attributes
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }

    // MARK: Helpers

    func indexPathsOfItems(inRect rect:CGRect) -> [IndexPath] {
        let minVisibleDay = dayIndexFromXCoordinate(rect.minX)
        let maxVisibleDay = dayIndexFromXCoordinate(rect.maxX)
        let minVisibleHour = hourIndexFromYCoordinate(rect.minY)
        let maxVisibleHour = hourIndexFromYCoordinate(rect.maxY)
        
        //    NSLog(@"rect: %@, days: %d-%d, hours: %d-%d", NSStringFromCGRect(rect), minVisibleDay, maxVisibleDay, minVisibleHour, maxVisibleHour);
        
        guard let dataSource = collectionView!.dataSource as? TierCollectionDataSource else {
            return []
        }
        let indexPaths = dataSource.indexPathsOfEvents(betweenMinDayIndex:minVisibleDay, maxDayIndex:maxVisibleDay,minStartHour:minVisibleHour,maxStartHour:maxVisibleHour)
        return indexPaths
    }


    func dayIndexFromXCoordinate(_ xPosition:CGFloat) -> Int {
        let contentWidth = collectionViewContentSize.width - HourHeaderWidth
        
        let widthPerDay = contentWidth / DaysPerWeek
        let dayIndex = max(Int(0), Int((xPosition - HourHeaderWidth) / widthPerDay))
        return dayIndex
    }

    func hourIndexFromYCoordinate(_ yPosition:CGFloat) -> Int {
        let hourIndex = max(Int(0), Int((yPosition - DayHeaderHeight) / HeightPerHour))
        return hourIndex
    }

    func indexPathsOfDayHeaderViews(inRect rect:CGRect) -> [IndexPath] {
        if (rect.minY > DayHeaderHeight) {
            return []
        }
        
        let minDayIndex = dayIndexFromXCoordinate(rect.minX)
        let maxDayIndex = dayIndexFromXCoordinate(rect.maxX)
        
        var indexPaths = [IndexPath]()
        for idx in minDayIndex..<maxDayIndex {
            let indexPath = IndexPath(item: idx, section: 0)
            indexPaths.append(indexPath)
        }
        return indexPaths
    }
    
    func indexPathsOfHourHeaderViews(inRect rect:CGRect) -> [IndexPath] {
        if (rect.minX > HourHeaderWidth) {
            return []
        }
        
        let minHourIndex = hourIndexFromYCoordinate(rect.minY)
        let maxHourIndex = hourIndexFromYCoordinate(rect.maxY)
        
        var indexPaths = [IndexPath]()
        for idx in minHourIndex..<maxHourIndex {
            let indexPath = IndexPath(item: idx, section: 0)
            indexPaths.append(indexPath)
        }
        return indexPaths
    }
    
    func frameForEvent(event:CalendarEvent) -> CGRect {
        let totalWidth = collectionViewContentSize.width - HourHeaderWidth
        let widthPerDay = totalWidth / DaysPerWeek
    
        var frame = CGRect.zero
        frame.origin.x = HourHeaderWidth + widthPerDay * CGFloat(event.day)
        frame.origin.y = DayHeaderHeight + HeightPerHour * CGFloat(event.startHour)
        frame.size.width = widthPerDay
        frame.size.height = CGFloat(event.durationInHours) * HeightPerHour
    
        return frame.insetBy(dx: HorizontalSpacing/2.0, dy: 0)
    }
}
