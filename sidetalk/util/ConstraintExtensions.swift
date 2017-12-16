
import Foundation

internal struct PartialConstraint {
    let item: AnyObject;
    let attr: NSLayoutConstraint.Attribute?;

    let constant: CGFloat;

    var left: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .left, constant: 0); } };
    var right: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .right, constant: 0); } };
    var top: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .top, constant: 0); } };
    var bottom: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .bottom, constant: 0); } };
    var width: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .width, constant: 0); } };
    var height: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .height, constant: 0); } };

    func my(_ attr: NSLayoutConstraint.Attribute) -> PartialConstraint {
        return PartialConstraint(item: self.item, attr: attr, constant: self.constant);
    }
}

func == (left: PartialConstraint, right: PartialConstraint) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .equal, toItem: right.item, attribute: right.attr!,
                              multiplier: 1.0, constant: right.constant - left.constant);
}

func <= (left: PartialConstraint, right: PartialConstraint) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .lessThanOrEqual, toItem: right.item, attribute: right.attr!,
                              multiplier: 1.0, constant: right.constant - left.constant);
}

func >= (left: PartialConstraint, right: PartialConstraint) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .greaterThanOrEqual, toItem: right.item, attribute: right.attr!,
                              multiplier: 1.0, constant: right.constant - left.constant);
}

func == (left: PartialConstraint, right: CGFloat) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .equal, toItem: nil, attribute: left.attr!,
                              multiplier: 0.0, constant: right - left.constant);
}

func <= (left: PartialConstraint, right: CGFloat) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .lessThanOrEqual, toItem: nil, attribute: left.attr!,
                              multiplier: 0.0, constant: right - left.constant);
}

func >= (left: PartialConstraint, right: CGFloat) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: left.attr!,
                              multiplier: 0.0, constant: right - left.constant);
}

func + (left: PartialConstraint, right: CGFloat) -> PartialConstraint {
    return PartialConstraint(item: left.item, attr: left.attr, constant: left.constant + right);
}

func - (left: PartialConstraint, right: CGFloat) -> PartialConstraint {
    return PartialConstraint(item: left.item, attr: left.attr, constant: left.constant - right);
}

extension NSView {
    var constrain: PartialConstraint { get { return PartialConstraint(item: self, attr: nil, constant: 0); } };
}
