#import "FloatingLogView.h"

@interface FloatingLogView ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation FloatingLogView

+ (instancetype)sharedInstance {
    static FloatingLogView *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithFrame:CGRectMake(20, 100, 300, 200)];
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        self.layer.cornerRadius = 10;

        _textView = [[UITextView alloc] initWithFrame:self.bounds];
        _textView.backgroundColor = UIColor.clearColor;
        _textView.textColor = UIColor.greenColor;
        _textView.font = [UIFont systemFontOfSize:12];
        _textView.editable = NO;
        [self addSubview:_textView];

        self.hidden = NO;
    }
    return self;
}

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *str = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *newText = [NSString stringWithFormat:@"%@\n%@", str, self.textView.text];
        self.textView.text = newText;
    });
}
@end
