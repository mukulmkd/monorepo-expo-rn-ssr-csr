// Copyright 2022-present 650 Industries. All rights reserved.

#ifdef __cplusplus

#import <vector>
#import <unordered_map>
#include <jsi/jsi.h>

namespace jsi = facebook::jsi;

// Use id instead of EXAppContext to avoid needing the Swift class definition
// EXAppContext is a Swift class (@objc(EXAppContext)) that will be available at runtime

namespace expo {

using SharedJSIObject = std::shared_ptr<jsi::Object>;
using UniqueJSIObject = std::unique_ptr<jsi::Object>;

class JSI_EXPORT ExpoModulesHostObject : public jsi::HostObject {
public:
  ExpoModulesHostObject(id appContext);

  virtual ~ExpoModulesHostObject();

  jsi::Value get(jsi::Runtime &, const jsi::PropNameID &name) override;

  void set(jsi::Runtime &, const jsi::PropNameID &name, const jsi::Value &value) override;

  std::vector<jsi::PropNameID> getPropertyNames(jsi::Runtime &rt) override;

private:
  id appContext;
  std::unordered_map<std::string, UniqueJSIObject> modulesCache;

}; // class ExpoModulesHostObject

} // namespace expo

#endif
