import * as React from "react";

export type NavigationContextType = {
  navigate: (route: string, params?: any) => void;
  canGoBack?: () => boolean;
  goBack?: () => void;
};

export const NavigationContext =
  React.createContext<NavigationContextType | null>(null);

export function useNavigation() {
  const context = React.useContext(NavigationContext);

  if (!context) {
    return {
      navigate: () => {},
      canGoBack: () => false,
      goBack: () => {},
    };
  }
  return context;
}
