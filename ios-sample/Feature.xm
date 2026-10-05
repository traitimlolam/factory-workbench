#import <UIKit/UIKit.h>

void FactoryFeatureDidStart(UIViewController *controller) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Factory Sample"
        message:@"Tweak mẫu đã khởi động." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
