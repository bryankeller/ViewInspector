import SwiftUI

// MARK: - Search namespace and types

@available(iOS 13.0, macOS 10.15, tvOS 13.0, *)
public struct ViewSearch {
    public enum Relation {
        case child
        case parent
    }
    public typealias Condition = (InspectableView<ViewType.ClassifiedView>) throws -> Bool
}

// MARK: - Public search API

@available(iOS 13.0, macOS 10.15, tvOS 13.0, *)
public extension InspectableView {
    
    func find(text: String) throws -> InspectableView<ViewType.Text> {
        return try find(textWhere: { value, _ in value == text })
    }
    
    func find(textWhere condition: (String, ViewType.Text.Attributes) throws -> Bool
    ) throws -> InspectableView<ViewType.Text> {
        return try find(ViewType.Text.self, where: {
            try condition(try $0.string(), try $0.attributes())
        })
    }
    
    func find(button: String) throws -> InspectableView<ViewType.Button> {
        let buttonType = ViewType.Button.self
        return try find(ViewType.Text.self, where: { text in
            (try? text.string()) == button &&
            (try? text.find(buttonType, relation: .parent)) != nil
        }).find(buttonType, relation: .parent)
    }
    
    func find(viewWithId id: AnyHashable) throws -> InspectableView<ViewType.ClassifiedView> {
        return try find { try $0.id() == id }
    }
    
    func find(viewWithTag tag: AnyHashable) throws -> InspectableView<ViewType.ClassifiedView> {
        return try find { try $0.tag() == tag }
    }
    
    func find<T>(_ viewType: T.Type,
                 relation: ViewSearch.Relation = .child,
                 where condition: (InspectableView<T>) throws -> Bool = { _ in true }
    ) throws -> InspectableView<T> where T: KnownViewType {
        let view = try find(relation: relation, where: { view -> Bool in
            guard let typedView = try? view.asInspectableView(ofType: T.self)
            else { return false }
            return (try? condition(typedView)) == true
        })
        return try view.asInspectableView(ofType: T.self)
    }
    
    func find(relation: ViewSearch.Relation = .child,
              where condition: ViewSearch.Condition
    ) throws -> InspectableView<ViewType.ClassifiedView> {
        switch relation {
        case .child:
            return try findChild(condition: condition)
        case .parent:
            return try findParent(condition: condition)
        }
    }
    
    func findAll<T>(_ viewType: T.Type,
                    where condition: (InspectableView<T>) throws -> Bool = { _ in true }
    ) -> [InspectableView<T>] where T: KnownViewType {
        return findAll(where: { view in
            guard let typedView = try? view.asInspectableView(ofType: T.self)
            else { return false }
            return (try? condition(typedView)) == true
        }).compactMap({ try? $0.asInspectableView(ofType: T.self) })
    }
    
    func findAll(where condition: ViewSearch.Condition) -> [InspectableView<ViewType.ClassifiedView>] {
        return depthFirstFullTraversal(condition)
            .compactMap { try? $0.asInspectableView() }
    }
}

// MARK: - Search

@available(iOS 13.0, macOS 10.15, tvOS 13.0, *)
private extension UnwrappedView {
    
    func findParent(condition: ViewSearch.Condition) throws -> InspectableView<ViewType.ClassifiedView> {
        var current = parentView
        while let parent = try? current?.asInspectableView() {
            if (try? condition(parent)) == true {
                return parent
            }
            current = parent.parentView
        }
        throw InspectionError.notSupported("Search did not find a match")
    }
    
    func findChild(condition: ViewSearch.Condition) throws -> InspectableView<ViewType.ClassifiedView> {
        var unknownViews: [Any] = []
        guard let result = breadthFirstSearch(condition, identificationFailure: { content in
            unknownViews.append(content.view)
        }) else {
            let blockers = unknownViews.count == 0 ? "" :
                ". Possible blockers: \(unknownViews.map({ Inspector.typeName(value: $0, prefixOnly: false) }))"
            throw InspectionError.notSupported("Search did not find a match" + blockers)
        }
        return try result.asInspectableView()
    }
    
    func breadthFirstSearch(_ condition: ViewSearch.Condition,
                            identificationFailure: (Content) -> Void) -> UnwrappedView? {
        var queue: [(isSingle: Bool, children: LazyGroup<UnwrappedView>)] = []
        queue.append((true, .init(count: 1, { _ in self })))
        while !queue.isEmpty {
            let (isSingle, children) = queue.remove(at: 0)
            for (offset, view) in children.enumerated() {
                if (try? condition(try view.asInspectableView())) == true {
                    return view
                }
                let index = (isSingle && offset == 0) ? nil : offset
                guard let identity = ViewSearch.identify(view.content),
                      let instance = try? identity.builder(view.content, view.parentView, index)
                else {
                    identificationFailure(view.content)
                    continue
                }
                if let descendants = try? identity.descendants(instance) {
                    let isSingle = (identity.viewType is SingleViewContent.Type) && descendants.count == 1
                    queue.append((isSingle, descendants))
                }
            }
        }
        return nil
    }
    
    func depthFirstFullTraversal(isSingle: Bool = true, offset: Int = 0,
                                 _ condition: ViewSearch.Condition) -> [UnwrappedView] {
        
        var current: [UnwrappedView] = []
        if (try? condition(try self.asInspectableView())) == true {
            current.append(self)
        }
        
        let index = (isSingle && offset == 0) ? nil : offset
        guard let identity = ViewSearch.identify(self.content),
              let instance = try? identity.builder(self.content, self.parentView, index),
              let descendants = try? identity.descendants(instance)
        else { return current }
        
        let isSingle = (identity.viewType is SingleViewContent.Type) && descendants.count == 1
        
        let joined = [current] + descendants.enumerated().map({ offset, child in
            child.depthFirstFullTraversal(isSingle: isSingle, offset: offset, condition)
        })
        return joined.flatMap { $0 }
    }
}
