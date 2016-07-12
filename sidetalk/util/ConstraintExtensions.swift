
import Foundation

internal struct PartialConstraint {
    let item: AnyObject;
    let attr: NSLayoutAttribute?;

    let constant: CGFloat;

    var left: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .Left, constant: 0); } };
    var right: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .Right, constant: 0); } };
    var top: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .Top, constant: 0); } };
    var bottom: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .Bottom, constant: 0); } };
    var width: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .Width, constant: 0); } };
    var height: PartialConstraint { get { return PartialConstraint(item: self.item, attr: .Height, constant: 0); } };

    func my(attr: NSLayoutAttribute) -> PartialConstraint {
        return PartialConstraint(item: self.item, attr: attr, constant: self.constant);
    }
}

func == (left: PartialConstraint, right: PartialConstraint) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .Equal, toItem: right.item, attribute: right.attr!,
                              multiplier: 1.0, constant: right.constant - left.constant);
}

func <= (left: PartialConstraint, right: PartialConstraint) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .LessThanOrEqual, toItem: right.item, attribute: right.attr!,
                              multiplier: 1.0, constant: right.constant - left.constant);
}

func >= (left: PartialConstraint, right: PartialConstraint) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .GreaterThanOrEqual, toItem: right.item, attribute: right.attr!,
                              multiplier: 1.0, constant: right.constant - left.constant);
}

func == (left: PartialConstraint, right: CGFloat) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .Equal, toItem: nil, attribute: left.attr!,
                              multiplier: 0.0, constant: right - left.constant);
}

func <= (left: PartialConstraint, right: CGFloat) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .LessThanOrEqual, toItem: nil, attribute: left.attr!,
                              multiplier: 0.0, constant: right - left.constant);
}

func >= (left: PartialConstraint, right: CGFloat) -> NSLayoutConstraint {
    return NSLayoutConstraint(item: left.item, attribute: left.attr!, relatedBy: .GreaterThanOrEqual, toItem: nil, attribute: left.attr!,
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
