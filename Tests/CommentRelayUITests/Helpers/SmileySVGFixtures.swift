// Tests/CommentRelayUITests/Helpers/SmileySVGFixtures.swift
// Verbatim copies of the SVG constants served by the CommentRelay API
// (see commentrelay-api/src/config/smiley-svgs.ts). If the API changes
// the shape family, update these fixtures to match.

enum SmileySVGFixtures {
    static let veryUnhappy = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="10" fill="#FF4444" stroke="#CC0000" stroke-width="1"/><circle cx="8.5" cy="9.5" r="1.5" fill="#CC0000"/><circle cx="15.5" cy="9.5" r="1.5" fill="#CC0000"/><path d="M8 17c1.5-2 6.5-2 8 0" stroke="#CC0000" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>"##

    static let unhappy = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="10" fill="#FF8844" stroke="#CC5500" stroke-width="1"/><circle cx="8.5" cy="9.5" r="1.5" fill="#CC5500"/><circle cx="15.5" cy="9.5" r="1.5" fill="#CC5500"/><path d="M9 16c1-1 5-1 6 0" stroke="#CC5500" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>"##

    static let neutral = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="10" fill="#FFCC44" stroke="#CC9900" stroke-width="1"/><circle cx="8.5" cy="9.5" r="1.5" fill="#CC9900"/><circle cx="15.5" cy="9.5" r="1.5" fill="#CC9900"/><line x1="8.5" y1="15" x2="15.5" y2="15" stroke="#CC9900" stroke-width="1.5" stroke-linecap="round"/></svg>"##

    static let happy = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="10" fill="#88CC44" stroke="#559900" stroke-width="1"/><circle cx="8.5" cy="9.5" r="1.5" fill="#559900"/><circle cx="15.5" cy="9.5" r="1.5" fill="#559900"/><path d="M9 14c1 1 5 1 6 0" stroke="#559900" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>"##

    static let veryHappy = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="10" fill="#44BB44" stroke="#228822" stroke-width="1"/><circle cx="8.5" cy="9.5" r="1.5" fill="#228822"/><circle cx="15.5" cy="9.5" r="1.5" fill="#228822"/><path d="M8 14c1.5 2 6.5 2 8 0" stroke="#228822" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>"##

    static let all = [veryUnhappy, unhappy, neutral, happy, veryHappy]
}
