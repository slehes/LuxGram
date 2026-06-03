import Foundation
import UIKit
import Display
import AccountContext
import TelegramPresentationData
import PresentationDataUtils

public func doubleBottomSettingsController(context: AccountContext) -> ViewController {
    let pd = context.sharedContext.currentPresentationData.with { $0 }
    let lang = pd.strings.baseLanguageCode
    let controller = textAlertController(
        context: context,
        title: lang == "ru" ? "Двойное дно" : "Double Bottom",
        text: lang == "ru" ? "Функция в разработке." : "Feature in development.",
        actions: [TextAlertAction(type: .defaultAction, title: pd.strings.Common_OK, action: {})]
    )
    return controller
}
