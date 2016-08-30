
import Foundation

class STCIShadow: CIFilter {
    var inputImage: CIImage?;

    override var outputImage: CIImage? { get {
        let monochromeFilter = CIFilter(name: "CIColorMatrix")!;
        monochromeFilter.setDefaults();
        monochromeFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector");
        monochromeFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector");
        monochromeFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector");
        monochromeFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector");
        monochromeFilter.setValue(self.inputImage!, forKey: "inputImage");

        let blurFilter = CIFilter(name: "CIGaussianBlur")!;
        blurFilter.setDefaults();
        blurFilter.setValue(4.0, forKey: "inputRadius");
        blurFilter.setValue(monochromeFilter.outputImage!, forKey: "inputImage");

        return self.inputImage!.imageByCompositingOverImage(blurFilter.outputImage!);
    } };
}
